import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.hid
import ChumCore

/// Turns Caps Lock into a "hyper" modifier (⌃⌥⇧⌘).
///
/// Caps Lock is not usable at the CGEvent level for this: each press toggles
/// the lock state and releases emit no event at all, so physical press/release
/// is detected with a passive `IOHIDManager` (the approach Hyperkey.app
/// takes). A session event tap then consumes the Caps Lock flagsChanged (the
/// lock never engages, a lone tap does nothing) and, while the key is held,
/// inserts the hyper modifiers into every event. Carbon hotkey matching and
/// shortcut recorders read event flags, so ⌃⌥⇧⌘+key works for Chum's
/// hotkeys and in any app in the session.
///
/// The tap and the HID monitor run on a DEDICATED thread's run loop, not the
/// main one: a busy main thread delays tap callbacks past the system's tap
/// timeout, which disables the tap (it is re-enabled on the timeout event,
/// but under sustained load it keeps bouncing) and makes hyper detection lag
/// for seconds — "hyper stops working while window commands (plain Carbon
/// hotkeys) keep working". A private run loop keeps event latency independent
/// of whatever the main thread is doing.
final class HyperkeyEngine: @unchecked Sendable {
    static let shared = HyperkeyEngine()

    /// Marks events we post so the tap ignores its own output.
    private static let syntheticTag: Int64 = 0x5472_6173_7448_7965

    private static let hyperFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    /// kVK_CapsLock
    private static let capsLockKeyCode: Int64 = 0x39
    /// HID usage page 0x07 (keyboard) / usage 0x39 (Caps Lock)
    private static let keyboardUsagePage: UInt32 = 0x07
    private static let capsLockUsage: UInt32 = 0x39
    /// Left cmd / option / control / shift keycodes, for synthetic
    /// flagsChanged events attributed per modifier key.
    private static let modifierKeycodes: [(keyCode: CGKeyCode, flag: CGEventFlags)] = [
        (0x37, .maskCommand),
        (0x3A, .maskAlternate),
        (0x3B, .maskControl),
        (0x38, .maskShift),
    ]
    /// kVK_F18 — the destination of the Caps Lock driver remap.
    private static let f18KeyCode: Int64 = 0x4F
    /// HID usage page 0x07 (keyboard), usage 0x39 (Caps Lock) remapped to
    /// usage 0x6D (F18) while the engine runs.
    private static let capsRemapJSON = """
    {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}
    """
    private static let capsRemapRevertJSON = """
    {"UserKeyMapping":[]}
    """

    /// The thread that owns the event tap, the HID monitor, and the
    /// engine-confined state below. Main only calls start()/stop()/restart();
    /// the lifecycle vars it touches are guarded by `stateLock`.
    private var engineThread: Thread?
    private var engineRunLoop: CFRunLoop?
    private var teardownSignal: DispatchSemaphore?
    private var setupSucceeded = false
    /// Tap/HID activity timestamps — the watchdog's inputs. The HID monitor
    /// sees raw keyboard input no matter what the session does (Secure
    /// Input, dead taps), so recent HID activity with a silent tap means the
    /// tap died silently.
    private var lastTapEventAt: Date?
    private var lastHIDEventAt: Date?
    private var lastRestartAt: Date?
    private var watchdogTimer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private let stateLock = NSLock()

    // Engine-thread-confined state — never touched from main while running.
    private var capsIsDown = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hidManager: IOHIDManager?
    private var didApplyCapsRemap = false
    // kCGEventSourceStatePrivate is not exposed as a Swift enum case; its raw
    // value is ~0. A private source isolates synthetic events from the shared
    // HID state so physical keys held during injection can't suppress them.
    private let injectSource = CGEventSource(stateID: CGEventSourceStateID(rawValue: -1)!)

    private init() {}

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return engineThread != nil
    }

    func start() {
        guard AppSettings.hyperKeyEnabled else { return }
        stateLock.lock()
        guard engineThread == nil else { stateLock.unlock(); return }
        stateLock.unlock()
        // The tap consumes and rewrites events, which requires Accessibility.
        guard Accessibility.isTrusted else { return }

        let ready = DispatchSemaphore(value: 0)
        let teardown = DispatchSemaphore(value: 0)
        let thread = Thread { [unowned self] in
            self.runEngine(ready: ready, teardown: teardown)
        }
        thread.name = "ChumHyperkeyEngine"
        thread.stackSize = 1 << 17

        stateLock.lock()
        engineThread = thread
        teardownSignal = teardown
        stateLock.unlock()
        thread.start()

        // Hold start() until the engine thread finished setup — stop() and
        // isRunning would otherwise race a thread that is still building (or
        // immediately failing) its tap.
        _ = ready.wait(timeout: .now() + 2)
        stateLock.lock()
        let succeeded = setupSucceeded
        stateLock.unlock()
        if !succeeded {
            // The thread tore itself down (tap creation failed, Input
            // Monitoring denied): clear the lifecycle so the next start()
            // can try again instead of pointing at a dead thread forever.
            stateLock.lock()
            engineThread = nil
            teardownSignal = nil
            stateLock.unlock()
            return
        }
        startWatchdog()
        startWakeObserver()
    }

    func stop() {
        stopWatchdog()
        stopWakeObserver()
        stateLock.lock()
        guard let thread = engineThread else { stateLock.unlock(); return }
        engineThread = nil
        let signal = teardownSignal
        teardownSignal = nil
        let runLoop = engineRunLoop
        stateLock.unlock()

        // The thread may have already torn itself down (failed setup).
        guard thread.isExecuting else { return }
        if let runLoop { CFRunLoopStop(runLoop) }
        // Give the thread time to unschedule/close/revert (hidutil can take
        // a moment); on timeout the engine finishes its own teardown alone.
        _ = signal?.wait(timeout: .now() + 2)
    }

    /// Rebuilds the engine — the watchdog and wake self-heal path. Main
    /// thread.
    func restart() {
        stop()
        start()
    }

    /// Engine thread: sets up the tap + HID monitor on this thread's run
    /// loop, signals `ready`, then services events until CFRunLoopStop —
    /// from stop() — ends the loop, and tears everything down.
    private func runEngine(ready: DispatchSemaphore, teardown: DispatchSemaphore) {
        let runLoop = CFRunLoopGetCurrent()
        stateLock.lock()
        engineRunLoop = runLoop
        setupSucceeded = false
        stateLock.unlock()

        let eventMask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
        )

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let engine = Unmanaged<HyperkeyEngine>.fromOpaque(userInfo).takeUnretainedValue()
            return engine.handleEvent(type: type, event: event).map { Unmanaged.passRetained($0) } ?? nil
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            stateLock.lock()
            engineRunLoop = nil
            stateLock.unlock()
            ready.signal()
            teardown.signal()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(runLoop, source, .defaultMode)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        startHIDMonitor()

        // Without press/release state the key cannot behave as a modifier at
        // all — tear down so Caps Lock keeps working normally (the settings
        // UI shows the missing-permission warning).
        guard hidManager != nil else {
            ready.signal()
            tearDownEngine()
            teardown.signal()
            return
        }

        applyCapsRemap()
        stateLock.lock()
        setupSucceeded = true
        stateLock.unlock()
        ready.signal()
        CFRunLoopRun()
        tearDownEngine()
        teardown.signal()
    }

    /// Engine thread: reverts the remap, releases modifiers, and removes the
    /// tap + HID monitor from this thread's run loop.
    private func tearDownEngine() {
        if didApplyCapsRemap {
            didApplyCapsRemap = false
            Self.runHidutil(["property", "--set", Self.capsRemapRevertJSON])
        }
        if capsIsDown {
            capsIsDown = false
            postHyperFlags(down: false)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        eventTap = nil
        runLoopSource = nil
        hidManager = nil
        stateLock.lock()
        engineRunLoop = nil
        stateLock.unlock()
    }

    /// Physical Caps Lock press/release only exists at the HID level.
    private func startHIDMonitor() {
        guard hidManager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ] as CFDictionary)

        let callback: IOHIDValueCallback = { context, _, _, value in
            guard let context else { return }
            let engine = Unmanaged<HyperkeyEngine>.fromOpaque(context).takeUnretainedValue()
            engine.handleHIDValue(value)
        }
        IOHIDManagerRegisterInputValueCallback(manager, callback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Opening keyboard devices for monitoring needs Input Monitoring;
        // prompt for it and try again on the next toggle if it was denied.
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            CGRequestListenEventAccess()
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return
        }

        hidManager = manager
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        markHIDEvent()
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == Self.keyboardUsagePage,
              IOHIDElementGetUsage(element) == Self.capsLockUsage
        else { return }

        let isDown = IOHIDValueGetIntegerValue(value) != 0
        guard isDown != capsIsDown else { return }
        capsIsDown = isDown
        postHyperFlags(down: isDown)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> CGEvent? {
        markTapEvent()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return event
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag {
            return event
        }

        // Fallback for when the driver remap did not apply: hide the caps
        // flagsChanged so its event never reaches apps. Note the HID-level
        // lock/LED state still changes — only the remap prevents that.
        if hidManager != nil,
           type == .flagsChanged,
           event.getIntegerValueField(.keyboardEventKeycode) == Self.capsLockKeyCode {
            return nil
        }

        // The driver remap turns caps presses into F18 key events; consume
        // them so apps never see a stray key (the HID monitor drives the
        // actual hyper state).
        if didApplyCapsRemap,
           type == .keyDown || type == .keyUp,
           event.getIntegerValueField(.keyboardEventKeycode) == Self.f18KeyCode {
            return nil
        }

        if capsIsDown {
            var flags = event.flags
            flags.insert(Self.hyperFlags)
            event.flags = flags
        }

        return event
    }

    /// Posts synthetic flagsChanged events so the session's modifier state
    /// reflects the hyper modifiers while Caps Lock is held. Chum's hotkeys
    /// do not depend on this (the tap rewrites the event flags), but
    /// modifier-state consumers and other apps' shortcut recorders do.
    private func postHyperFlags(down: Bool) {
        let base = CGEventSource.flagsState(.combinedSessionState)
            .subtracting(.maskAlphaShift)

        var flags = base
        if down {
            for (keyCode, flag) in Self.modifierKeycodes {
                flags = flags.union(flag)
                postFlagsChanged(keyCode: keyCode, flags: flags)
            }
        } else {
            for (keyCode, flag) in Self.modifierKeycodes.reversed() {
                flags = flags.subtracting(flag)
                postFlagsChanged(keyCode: keyCode, flags: flags)
            }
        }
    }

    private func postFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: injectSource, virtualKey: keyCode, keyDown: true) else { return }
        event.type = .flagsChanged
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        event.post(tap: .cgSessionEventTap)
    }

    // MARK: - Self-healing
    //
    // Taps die silently more often than they die loudly: wake-from-sleep
    // frequently leaves a session tap receiving nothing (with no disabled
    // notification delivered), and Secure-Input aftermath can too. The HID
    // monitor is the ground truth — it sees raw keyboard input no matter
    // what the session does — so recent typing that reached HID but not the
    // tap means the tap is dead and the engine needs rebuilding.

    private func markTapEvent() {
        stateLock.lock()
        lastTapEventAt = Date()
        stateLock.unlock()
    }

    private func markHIDEvent() {
        stateLock.lock()
        lastHIDEventAt = Date()
        stateLock.unlock()
    }

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 20, repeating: 20)
        timer.setEventHandler { [weak self] in self?.checkHealth() }
        timer.resume()
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    private func checkHealth() {
        stateLock.lock()
        guard engineThread != nil else { stateLock.unlock(); return }
        let hid = lastHIDEventAt
        let tap = lastTapEventAt
        let lastRestart = lastRestartAt
        stateLock.unlock()

        // No recent typing: nothing to conclude — an idle machine with a
        // dead tap looks identical to an idle machine with a live one.
        guard let hid, Date().timeIntervalSince(hid) < 20 else { return }
        let tapSilent = tap.map { Date().timeIntervalSince($0) > 20 } ?? true
        guard tapSilent else { return }
        // Rate-limit: while Secure Input is active (password prompts) taps
        // legitimately receive nothing, and rebuilding won't help — don't
        // restart-storm.
        if let lastRestart, Date().timeIntervalSince(lastRestart) < 60 { return }

        stateLock.lock()
        lastRestartAt = Date()
        stateLock.unlock()
        NSLog("Chum Hyperkey: event tap stopped receiving events — rebuilding engine")
        DispatchQueue.main.async { [weak self] in self?.restart() }
    }

    private func startWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Give the session a moment to settle, then rebuild the engine.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.isRunning else { return }
                NSLog("Chum Hyperkey: rebuilding engine after wake")
                self.restart()
            }
        }
    }

    private func stopWakeObserver() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    /// Remaps Caps Lock to F18 at the HID driver level while the engine runs
    /// and reverts on stop. The keyboard lock/LED logic lives below the
    /// CGEvent layer, so consuming the flagsChanged alone does not stop the
    /// LED — the remap keeps the caps usage from ever reaching it (the
    /// technique Hyperkey.app uses). Mappings reset on reboot, so a crash can
    /// leave caps as F18 until the next toggle or reboot; the remap also
    /// replaces any personal Caps Lock remap set in System Settings.
    private func applyCapsRemap() {
        didApplyCapsRemap = Self.runHidutil(["property", "--set", Self.capsRemapJSON])
    }

    @discardableResult
    private static func runHidutil(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
