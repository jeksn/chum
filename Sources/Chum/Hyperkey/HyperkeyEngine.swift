import AppKit
import CoreGraphics
import Foundation
import ChumCore

/// Turns Caps Lock into a "hyper" modifier (⌃⌥⇧⌘).
///
/// Detection lives ENTIRELY in the session event tap — the design of
/// feedthejim/hyperkey, which never exhibits the "died silently" failure
/// our earlier IOHIDManager-based engine kept hitting:
///
/// 1. hidutil remaps Caps Lock to F18 at the driver level (so the lock
///    state and LED never engage).
/// 2. The tap watches F18 keyDown/keyUp — hyper down/up state — and
///    consumes them so apps never see a stray key.
/// 3. Fallback: when the remap is NOT applied, caps presses arrive as
///    flagsChanged (keycode 0x39) — alphaShift present = down — and the
///    tap consumes those instead. (The HID-level lock state still changes
///    on that path; only the remap fully prevents it.)
/// 4. While hyper is held, the tap inserts the four modifiers into every
///    event's flags — Carbon hotkey matching and recorders read event
///    flags, so ⌃⌥⇧⌘+key works for Chum's hotkeys and in any app in the
///    session.
///
/// There is no IOHIDManager: a passive HID monitor can silently stop
/// delivering (keyboard re-enumeration, sleep/wake), which leaves the tap
/// healthy but hyper dead — a state a watchdog can't even see, since no
/// HID events reads as "user idle". One component, one failure domain: if
/// the tap is dead nothing works anyway, and the system's
/// tapDisabledByTimeout notification re-enables it.
///
/// The tap runs on a DEDICATED thread's run loop, not the main one — a busy
/// main thread delays tap callbacks past the system's tap timeout, which
/// disables the tap; a private run loop keeps event latency independent of
/// whatever the main thread is doing. A didWake observer rebuilds the
/// engine after sleep, the one known silent killer of session taps.
final class HyperkeyEngine: @unchecked Sendable {
    static let shared = HyperkeyEngine()

    /// Marks events we post so the tap ignores its own output.
    private static let syntheticTag: Int64 = 0x5472_6173_7448_7965

    private static let hyperFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    /// kVK_CapsLock
    private static let capsLockKeyCode: Int64 = 0x39
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

    /// The thread that owns the event tap and the engine-confined state
    /// below. Main only calls start()/stop()/restart(); the lifecycle vars
    /// it touches are guarded by `stateLock`.
    private var engineThread: Thread?
    private var engineRunLoop: CFRunLoop?
    private var teardownSignal: DispatchSemaphore?
    private var setupSucceeded = false
    private var wakeObserver: NSObjectProtocol?
    private let stateLock = NSLock()

    // Engine-thread-confined state — never touched from main while running.
    private var capsIsDown = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
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
            // The thread tore itself down (tap creation failed): clear the
            // lifecycle so the next start() can try again instead of
            // pointing at a dead thread forever.
            stateLock.lock()
            engineThread = nil
            teardownSignal = nil
            stateLock.unlock()
            return
        }
        startWakeObserver()
    }

    func stop() {
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

    /// Rebuilds the engine — the wake self-heal path. Main thread.
    func restart() {
        stop()
        start()
    }

    /// Engine thread: sets up the tap on this thread's run loop, signals
    /// `ready`, then services events until CFRunLoopStop — from stop() —
    /// ends the loop, and tears everything down.
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

        applyCapsRemap()
        if !didApplyCapsRemap {
            NSLog("Chum Hyperkey: hidutil remap not applied — running on the caps flagsChanged fallback")
        }
        stateLock.lock()
        setupSucceeded = true
        stateLock.unlock()
        ready.signal()
        CFRunLoopRun()
        tearDownEngine()
        teardown.signal()
    }

    /// Engine thread: reverts the remap, releases modifiers, and removes the
    /// tap from this thread's run loop.
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
        eventTap = nil
        runLoopSource = nil
        stateLock.lock()
        engineRunLoop = nil
        stateLock.unlock()
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> CGEvent? {
        // The system disables the tap when the callback times out; the
        // notification is delivered here and re-arms it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return event
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag {
            return event
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // The driver remap turns caps presses into F18 key events — the
        // primary hyper signal. Consume them and track down/up state.
        if keyCode == Self.f18KeyCode {
            let isDown = type == .keyDown
            if isDown != capsIsDown {
                capsIsDown = isDown
                postHyperFlags(down: isDown)
            }
            return nil
        }

        // Fallback for when the driver remap did not apply: caps arrives as
        // flagsChanged, alphaShift present = down. Consume it so the lock
        // never engages at the CG level. (The HID-level lock/LED state
        // still changes on this path — only the remap fully prevents that.)
        if type == .flagsChanged, keyCode == Self.capsLockKeyCode {
            let isDown = event.flags.contains(.maskAlphaShift)
            if isDown != capsIsDown {
                capsIsDown = isDown
                postHyperFlags(down: isDown)
            }
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
    // With detection inside the tap there is one failure domain: a dead tap
    // means the callback isn't running at all, which the timeout
    // notification covers. The remaining silent killer is wake-from-sleep,
    // so the engine rebuilds once after the machine wakes.

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
