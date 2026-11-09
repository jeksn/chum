import AppKit
import CoreGraphics
import Foundation
import ChumCore

final class SnippetExpander {
    static let shared = SnippetExpander()

    /// Marks events we inject so the tap ignores its own output instead of
    /// feeding expansion text back into the keystroke buffer.
    private static let syntheticTag: Int64 = 0x5770_536E_6970
    /// Pause before selecting the keyword: lets the final physical keystroke
    /// finish so synthetic events never race real ones still in flight.
    private static let settleInterval: TimeInterval = 0.03
    /// Gap between a synthetic keyDown and its keyUp: zero-length presses get
    /// filtered as noise by some apps.
    private static let keyPressInterval: TimeInterval = 0.006
    /// Pacing between erase keystrokes (backspaces). Unlike text-generating
    /// events (which coalesce and drop characters below ~12ms), plain
    /// backspace events are safe to post almost back-to-back; the gap only
    /// needs to keep the presses distinct.
    private static let eraseInterval: TimeInterval = 0.002
    /// Pause between the selection phase and the paste so the app has
    /// processed the selection before the paste replaces it.
    private static let phaseInterval: TimeInterval = 0.015
    /// How long the expansion stays on the pasteboard before the user's
    /// clipboard content is restored.
    private static let clipboardRestoreInterval: TimeInterval = 0.25
    /// The typed buffer never grows past this; a delimiter always resets it
    /// long before, this only bounds the pathological case.
    private static let bufferLimit = 64

    // Lifecycle vars — touched from main, guarded by `stateLock`.
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var teardownSignal: DispatchSemaphore?
    private var setupSucceeded = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var clickMonitor: Any?
    private var appChangeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var snippetObserver: NSObjectProtocol?
    private var keyWindowObservers: [NSObjectProtocol] = []
    /// Incremented for every real keyDown the tap observes. An expansion
    /// captures the value at match time and aborts if any keystroke lands
    /// before its selection sweep starts — otherwise the sweep would select
    /// the wrong range (keyword + the extra typed characters), leaving
    /// residue instead of expanding ("stuck on the trigger").
    private var keystrokeGeneration = 0
    /// Polls for the Input Monitoring grant while it's missing (guarded by
    /// `stateLock`; started from main, fires on a utility queue).
    private var permissionRetryTimer: DispatchSourceTimer?
    private let stateLock = NSLock()

    // Maintained on the MAIN thread only (key-window notifications, app
    // activation, start/stop); the tap thread reads them under `stateLock`.
    // Reading `NSApp.keyWindow` from the tap callback is not thread-safe and
    // adds latency to a callback that must stay fast or the system disables
    // the tap.
    private var selfWindowIsKey = false
    /// Snapshot of the enabled snippets, refreshed on the main thread when
    /// the store changes, so the tap thread never touches the ObservableObject.
    private var snippetSnapshot: [Snippet] = []

    // Typed context — written from the tap thread and cleared from main
    // (click/app-change/wake observers), so all access takes `stateLock`.
    private var buffer = ""
    private let injectQueue = DispatchQueue(label: "com.chum.snippet.inject", qos: .userInteractive)
    // kCGEventSourceStatePrivate is not exposed as a Swift enum case; its raw
    // value is ~0. A private source isolates synthetic events from the shared
    // HID state so physical keys held during expansion can't suppress them —
    // used for the selection sweep.
    private let injectSource = CGEventSource(stateID: CGEventSourceStateID(rawValue: -1)!)
    /// The paste key goes through the HID system source instead — the same
    /// recipe as the launcher's paste-on-select, which is the path proven to
    /// reach menu shortcuts (Cmd+V) in target apps.
    private let pasteSource = CGEventSource(stateID: .hidSystemState)

    private init() {}

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return eventTap != nil
    }

    func start() {
        cancelPermissionRetry()
        guard AppSettings.snippetsEnabled else { return }
        stateLock.lock()
        guard tapThread == nil else { stateLock.unlock(); return }
        stateLock.unlock()
        guard ensureInputMonitoringPermission() else {
            // Permission often arrives while the app is already running
            // (System Settings toggling) — re-check periodically and create
            // the tap the moment it lands, instead of staying inactive
            // until the next relaunch.
            NSLog("Chum Snippets: Input Monitoring not granted — expansion starts as soon as the permission is granted in System Settings")
            schedulePermissionRetry()
            return
        }

        let ready = DispatchSemaphore(value: 0)
        let teardown = DispatchSemaphore(value: 0)
        let thread = Thread { [unowned self] in
            self.runTapLoop(ready: ready, teardown: teardown)
        }
        thread.name = "ChumSnippetTap"
        thread.stackSize = 1 << 17

        stateLock.lock()
        tapThread = thread
        teardownSignal = teardown
        stateLock.unlock()
        thread.start()

        // Hold start() until the tap thread finished setup — stop() and
        // isRunning would otherwise race a thread still building its tap.
        _ = ready.wait(timeout: .now() + 2)
        stateLock.lock()
        let succeeded = setupSucceeded
        stateLock.unlock()
        if !succeeded {
            stateLock.lock()
            tapThread = nil
            teardownSignal = nil
            stateLock.unlock()
            return
        }
        installClickMonitor()
        observeAppChanges()
        observeSnippetChanges()
        installKeyWindowObservers()
        refreshSnippetSnapshot()
        updateSelfKeyWindow()
        startWakeObserver()
    }

    func stop() {
        stopWakeObserver()
        cancelPermissionRetry()
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        if let appChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appChangeObserver)
        }
        if let snippetObserver {
            NotificationCenter.default.removeObserver(snippetObserver)
        }
        for observer in keyWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        clickMonitor = nil
        appChangeObserver = nil
        snippetObserver = nil
        keyWindowObservers = []
        clearBuffer()

        stateLock.lock()
        guard let thread = tapThread else { stateLock.unlock(); return }
        tapThread = nil
        let signal = teardownSignal
        teardownSignal = nil
        let runLoop = tapRunLoop
        stateLock.unlock()

        // The thread may have already torn itself down (failed setup).
        guard thread.isExecuting else { return }
        if let runLoop { CFRunLoopStop(runLoop) }
        // On timeout the tap thread finishes its own teardown alone.
        _ = signal?.wait(timeout: .now() + 2)
    }

    func restart() {
        stop()
        start()
    }

    // MARK: - Permission retry
    //
    // The tap dies at launch when Input Monitoring is missing; this poll
    // revives expansion the moment the user grants it in System Settings —
    // without it, granting while Chum is running leaves snippets dead until
    // a relaunch.

    private func schedulePermissionRetry() {
        stateLock.lock()
        guard permissionRetryTimer == nil else { stateLock.unlock(); return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if !AppSettings.snippetsEnabled {
                self.cancelPermissionRetry()
                return
            }
            // Preflight only — never re-request: the request alert already
            // fired once from start(), the rest happens in System Settings.
            guard CGPreflightListenEventAccess() else { return }
            self.cancelPermissionRetry()
            DispatchQueue.main.async { self.start() }
        }
        timer.resume()
        permissionRetryTimer = timer
        stateLock.unlock()
    }

    private func cancelPermissionRetry() {
        stateLock.lock()
        permissionRetryTimer?.cancel()
        permissionRetryTimer = nil
        stateLock.unlock()
    }

    private func ensureInputMonitoringPermission() -> Bool {
        if CGPreflightListenEventAccess() { return true }
        CGRequestListenEventAccess()
        return CGPreflightListenEventAccess()
    }

    /// Tap thread: creates the listen tap on its own run loop — never the
    /// main one, so a busy main thread can't delay keystroke observation
    /// past the system's tap timeout (which permanently disabled the tap in
    /// the old main-loop build and silently killed expansion).
    private func runTapLoop(ready: DispatchSemaphore, teardown: DispatchSemaphore) {
        let runLoop = CFRunLoopGetCurrent()
        stateLock.lock()
        tapRunLoop = runLoop
        setupSucceeded = false
        stateLock.unlock()

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let expander = Unmanaged<SnippetExpander>.fromOpaque(userInfo).takeUnretainedValue()
            return expander.handleEvent(type: type, event: event) ? Unmanaged.passRetained(event) : nil
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Chum Snippets: event tap creation failed — expansion inactive (Input Monitoring permission?)")
            stateLock.lock()
            tapRunLoop = nil
            stateLock.unlock()
            ready.signal()
            teardown.signal()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        stateLock.lock()
        eventTap = tap
        runLoopSource = source
        setupSucceeded = true
        stateLock.unlock()
        ready.signal()
        CFRunLoopRun()

        // Tap thread teardown.
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        stateLock.lock()
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        stateLock.unlock()
        teardown.signal()
    }

    /// Clicking into another field invalidates the typed context.
    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.clearBuffer()
        }
    }

    /// Switching apps invalidates the typed context.
    private func observeAppChanges() {
        guard appChangeObserver == nil else { return }
        appChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearBuffer()
            self?.updateSelfKeyWindow()
        }
    }

    /// Re-snapshots the enabled snippets on every store mutation (main
    /// thread) so the tap thread matches against a plain array.
    private func observeSnippetChanges() {
        guard snippetObserver == nil else { return }
        snippetObserver = NotificationCenter.default.addObserver(
            forName: SnippetStore.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSnippetSnapshot()
        }
    }

    private func refreshSnippetSnapshot() {
        let snapshot = SnippetStore.shared.validSnippets
        stateLock.lock()
        snippetSnapshot = snapshot
        stateLock.unlock()
    }

    /// Key-window changes decide whether keystrokes land in Chum's own UI
    /// (launcher search, settings fields — never expanded). AppKit is only
    /// touched here, on the main thread; the tap thread reads the flag.
    private func installKeyWindowObservers() {
        guard keyWindowObservers.isEmpty else { return }
        let center = NotificationCenter.default
        keyWindowObservers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
                self?.updateSelfKeyWindow()
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
                self?.updateSelfKeyWindow()
            },
        ]
    }

    private func updateSelfKeyWindow() {
        let isKey = NSApp.keyWindow != nil
        stateLock.lock()
        selfWindowIsKey = isKey
        stateLock.unlock()
    }

    private func startWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.isRunning else { return }
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

    // MARK: - Typed buffer
    //
    // Every access takes `stateLock`: the tap thread appends/reads, and the
    // main thread clears (clicks, app switches, stop, wake).

    private func clearBuffer() {
        stateLock.lock()
        buffer = ""
        stateLock.unlock()
    }

    private func backspaceBuffer() {
        stateLock.lock()
        if !buffer.isEmpty { buffer.removeLast() }
        stateLock.unlock()
    }

    private func appendBuffer(_ char: Character) {
        stateLock.lock()
        buffer.append(char)
        if buffer.count > Self.bufferLimit { buffer = "" }
        stateLock.unlock()
    }

    private var currentBuffer: String {
        stateLock.lock(); defer { stateLock.unlock() }
        return buffer
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        // The system disables the tap when the callback times out; the
        // notification is delivered here and re-arms it. The old build had
        // no re-arm — one slow callback (busy main thread) killed expansion
        // permanently and silently. Re-arm asynchronously: re-enabling
        // synchronously inside the callback can immediately re-trigger the
        // disable condition.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            NSLog("Chum Snippets: event tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")) — re-arming; keystrokes in this window were missed")
            stateLock.lock()
            let tap = eventTap
            stateLock.unlock()
            if let tap {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self else { return }
                    self.stateLock.lock()
                    let current = self.eventTap
                    self.stateLock.unlock()
                    if current == tap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }
            }
            return true
        }

        guard type == .keyDown else { return true }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag {
            return true
        }

        stateLock.lock()
        keystrokeGeneration += 1
        let selfKey = selfWindowIsKey
        stateLock.unlock()

        // Keystrokes landing in Chum's own UI (launcher search, settings
        // fields) never expand: editing a snippet's keyword in Settings must
        // not fire the snippet. Our panel/windows are the key window only
        // while the user is actually typing into them. The flag is maintained
        // on the main thread — AppKit is never touched from this callback.
        if selfKey {
            clearBuffer()
            return true
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskControl) {
            // Modified keystrokes (paste, select all, shortcuts) never produce
            // contiguous typed text.
            clearBuffer()
            return true
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch keyCode {
        case 36, 76:
            clearBuffer()
            return true
        case 53:
            clearBuffer()
            return true
        case 48:
            clearBuffer()
            return true
        case 49:
            clearBuffer()
            return true
        case 51:
            backspaceBuffer()
            return true
        default:
            break
        }

        var actualLength: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let maxLen = chars.count
        event.keyboardGetUnicodeString(maxStringLength: maxLen, actualStringLength: &actualLength, unicodeString: &chars)

        // Keys that produce no text (arrows, function keys, Home/End, forward
        // delete) mean the cursor moved: the typed text is no longer contiguous.
        guard actualLength > 0 else {
            clearBuffer()
            return true
        }

        let charString = String(utf16CodeUnits: chars, count: actualLength)
        guard let char = charString.first else {
            clearBuffer()
            return true
        }

        if char.isWhitespace {
            clearBuffer()
            return true
        }

        appendBuffer(char)

        if let match = matchingSnippet() {
            stateLock.lock()
            let generation = keystrokeGeneration
            stateLock.unlock()
            clearBuffer()
            expand(keyword: match.keyword, into: match.content, generation: generation)
        }

        return true
    }

    private func matchingSnippet() -> Snippet? {
        stateLock.lock()
        let buffer = self.buffer
        let snippets = self.snippetSnapshot
        stateLock.unlock()
        guard !buffer.isEmpty else { return nil }
        return snippets.first { $0.keyword == buffer }
    }

    /// Terminals turn arrow keys into escape sequences instead of moving the
    /// cursor, so the expander never sends arrows: the key-event erase is
    /// always backspaces, which are safe at a shell prompt (no autocomplete
    /// suggestion for a backspace to eat). This list is only a fast path that
    /// skips AX probing for known terminal emulators — any app whose focused
    /// element exposes no AX text value lands on the backspace path by
    /// capability as well, so unlisted terminals (WezTerm, a shell inside an
    /// editor, …) are covered too.
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "org.xquartz.X11",
    ]

    /// Chromium-family apps — browsers AND Electron editors (Obsidian,
    /// VS Code, …) — where a synthetic Cmd+V is unreliable in web fields
    /// (Chromium drops the event): the paste-fallback tier goes through the
    /// Edit → Paste menu item via AX instead. Reaching this tier in an
    /// Electron editor is common: Chromium exposes its accessibility tree
    /// lazily, so the first expansion in a cold document often misses the AX
    /// tiers entirely and relies on this paste path.
    private static let chromiumPasteBundleIDs: Set<String> = [
        "net.imput.helium",
        "com.google.Chrome",
        "com.brave.Browser",
        "org.chromium.Chromium",
        "com.microsoft.edgemac",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "md.obsidian",
        "com.microsoft.VSCode",
        "notion.id",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "org.whispersystems.signal-desktop",
    ]

    private static var frontmostIsTerminal: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            .map(terminalBundleIDs.contains) ?? false
    }

    private static var frontmostNeedsMenuPaste: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            .map(chromiumPasteBundleIDs.contains) ?? false
    }

    /// Expands in tiers, most reliable first:
    ///
    /// 1. AX selection replace: read the focused element's value and selected
    ///    text range, point the range at the typed keyword ourselves, and set
    ///    kAXSelectedTextAttribute to the expansion — atomic, no synthetic
    ///    key events, no visible highlight, and it preserves rich-text
    ///    formatting. Works in native apps, browsers (including the omnibox,
    ///    whose inline autocomplete is a live selection right after the typed
    ///    text and gets replaced together with the keyword), and editor/
    ///    Electron fields that expose AX text.
    /// 2. AX value rewrite: replace the whole kAXValueAttribute with the
    ///    keyword swapped for the expansion (fields that expose a value but
    ///    not a settable selection), verified by reading the value back so a
    ///    read-only element that ignores the set can't cause a double insert
    ///    on the fallback path.
    /// 3. Key events: backspace the keyword and paste — pasteboard +
    ///    synthetic Cmd+V, or the Edit → Paste menu item via AX in
    ///    Chromium-family apps (browser fields AND Electron editors —
    ///    Obsidian, VS Code — drop a synthetic Cmd+V in web fields).
    ///    Terminals skip tiers 1–2 and go straight here.
    ///
    /// Synthetic ARROW keys are never sent: terminals turn them into escape
    /// sequences that leak into the shell ("!zsh" -> "!zshDDDD…"). Backspaces
    /// are safe everywhere that reaches tier 3 — the omnibox-style autocomplete
    /// that eats a backspace lives in AX-capable fields handled by tiers 1–2,
    /// and a shell prompt has no suggestion to eat. Synthetic typing of the
    /// expansion is never used either: it must be paced ~12ms/char (below that
    /// events coalesce and characters drop), so long expansions streamed
    /// visibly for hundreds of milliseconds; a paste or an AX set lands in a
    /// single frame.
    ///
    /// `generation` is the keystroke count at match time; if any real
    /// keystroke lands before the expansion starts (fast typing after the
    /// keyword, a lagging app), the computed range would cover the wrong
    /// text — abort instead of mangling it.
    private func expand(keyword: String, into expansion: String, generation: Int) {
        // Everything below the generation guard runs off the tap thread: the
        // pasteboard read, template resolution, AX round trips, and
        // clipboard-history suspension all happen here, so the tap callback
        // only appends to the buffer and matches — staying fast enough that
        // the system never times it out.
        injectQueue.asyncAfter(deadline: .now() + Self.settleInterval) { [weak self] in
            guard let self else { return }

            stateLock.lock()
            let currentGeneration = keystrokeGeneration
            stateLock.unlock()
            guard currentGeneration == generation else {
                // A keystroke landed between the match and the expansion —
                // the range computed from the probe would be wrong. Abort.
                return
            }

            // Read-only clipboard access for template resolution — the
            // pasteboard is only borrowed (and capture suspended) in the paste
            // paths, when the AX paths didn't apply.
            let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
            let resolved = SnippetTemplate.resolve(expansion, clipboardContent: clipboard)

            if Self.frontmostIsTerminal {
                self.eraseWithBackspaces(keyword.count)
                self.paste(resolved)
                return
            }

            // Both AX tiers need the Accessibility grant — without it every
            // probe fails immediately, and with the cold-tree poll below the
            // budget roll-forward would turn each expansion into a ~1.2s
            // wait before the (working) key-event tier.
            if Accessibility.isTrusted,
               let probe = Self.awaitTextProbe(keyword: keyword) {
                if Self.replaceSelectionViaAX(probe, keyword: keyword, expansion: resolved) { return }
                if Self.replaceValueViaAX(keyword: keyword, expansion: resolved) { return }
            }

            // No AX text (an unlisted terminal, or an app that exposes none):
            // erase with backspaces, then paste.
            self.eraseWithBackspaces(keyword.count)
            if Self.frontmostNeedsMenuPaste {
                self.pasteViaChromiumMenu(resolved)
            } else {
                self.paste(resolved)
            }
        }
    }

    // MARK: - AX text surgery
    //
    // The focused element's text is read and written through Accessibility
    // instead of synthetic arrow keys: no escape-byte leaks, no selection
    // sweep that some fields ignore, no leftover highlight when the insert
    // is dropped.

    /// Upper bound on the value we are willing to read/rewrite — terminal
    /// scrollback and huge documents are excluded, which also routes them to
    /// the backspace path.
    private static let axValueSizeCap = 200_000

    private struct AXTextProbe {
        let element: AXUIElement
        let value: String
        let selectionStart: Int  // UTF-16 offsets, matching AX/CFRange
        let selectionLength: Int
    }

    /// Why a probe returned no text, when it did: `noFocusedElement` is the
    /// cold-tree state (keep probing — waiting can still pay off), while
    /// `noEditableText` means a focused element resolved but the text tiers
    /// can never apply to it (waiting is wasted — fall through fast).
    private enum AXTextProbeOutcome {
        case probe(AXTextProbe)
        case noFocusedElement
        case noEditableText
    }

    /// The focused element's value + selected text range, or why that
    /// couldn't be read.
    private static func probeFocusedText() -> AXTextProbeOutcome {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return .noFocusedElement }
        let focused = focusedValue as! AXUIElement

        // Skip huge values (terminal scrollback, big documents) without
        // reading them.
        var charCountRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXNumberOfCharactersAttribute as CFString, &charCountRef) == .success,
           let count = (charCountRef as? NSNumber)?.intValue, count > axValueSizeCap {
            return .noEditableText
        }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String,
              value.utf16.count <= axValueSizeCap else { return .noEditableText }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return .noEditableText }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else { return .noEditableText }

        return .probe(AXTextProbe(element: focused, value: value,
                                  selectionStart: range.location, selectionLength: range.length))
    }

    /// Budget for the typed keyword to show up at the caret/selection once
    /// AX resolves an element (apps process the final keystroke
    /// asynchronously, so the value read right after the match can lag).
    private static let probeInterval: TimeInterval = 0.15
    /// Hard cap while AX returns no focused element at all. Chromium-family
    /// apps (browsers AND Electron editors — Obsidian, VS Code, …) build
    /// the accessibility tree LAZILY: the first query from a new client can
    /// return nothing for hundreds of milliseconds. Without the extension,
    /// the first expansion attempt in a cold document burns the whole probe
    /// budget, falls to the erase+paste tier — and in Chromium family the
    /// synthetic ⌘-V is dropped, so the keyword is erased with nothing
    /// pasted: the "works on the second try, never the first" symptom. The
    /// tree stays warm after that first query, so the cost is one-time.
    private static let coldTreeProbeInterval: TimeInterval = 0.6

    /// Probes until the typed keyword shows up at the caret/selection —
    /// short budget once an element resolves, extended (up to the hard cap)
    /// while the AX tree is still cold and no element resolves at all.
    private static func awaitTextProbe(keyword: String) -> AXTextProbe? {
        let hardDeadline = Date().addingTimeInterval(Self.coldTreeProbeInterval)
        var deadline = Date().addingTimeInterval(Self.probeInterval)
        var seenElement = false
        while Date() < deadline {
            switch probeFocusedText() {
            case .probe(let probe):
                seenElement = true
                if SnippetTextEdit.replacementRange(value: probe.value,
                                                    selectionStart: probe.selectionStart,
                                                    selectionLength: probe.selectionLength,
                                                    keyword: keyword) != nil {
                    return probe
                }
            case .noEditableText:
                seenElement = true
            case .noFocusedElement:
                break
            }
            // Cold tree: roll the budget forward, bounded by the hard cap.
            // A resolved element keeps the remaining (short) budget as is.
            if !seenElement {
                let extended = Date().addingTimeInterval(Self.probeInterval)
                if extended < hardDeadline {
                    deadline = extended
                }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    private static func setSelectedRange(of element: AXUIElement, _ range: CFRange) -> Bool {
        var cfRange = range
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    /// Tier 1: point the selected text range at the keyword via AX (no
    /// synthetic arrow keys), then replace the selection with the expansion
    /// in one kAXSelectedTextAttribute set. Verified by read-back, and on
    /// failure the original selection is restored so a later backspace
    /// fallback doesn't delete more than the keyword.
    private static func replaceSelectionViaAX(_ probe: AXTextProbe, keyword: String, expansion: String) -> Bool {
        guard let range = SnippetTextEdit.replacementRange(value: probe.value,
                                                           selectionStart: probe.selectionStart,
                                                           selectionLength: probe.selectionLength,
                                                           keyword: keyword) else { return false }
        let expected = SnippetTextEdit.replacedValue(value: probe.value, range: range, expansion: expansion)
        guard setSelectedRange(of: probe.element, CFRange(location: range.location, length: range.length)),
              AXUIElementSetAttributeValue(probe.element, kAXSelectedTextAttribute as CFString, expansion as CFTypeRef) == .success,
              Self.verifyApplied(element: probe.element, expected: expected, insertLocation: range.location, expansion: expansion)
        else {
            _ = setSelectedRange(of: probe.element, CFRange(location: probe.selectionStart, length: probe.selectionLength))
            return false
        }
        _ = setSelectedRange(of: probe.element, CFRange(location: SnippetTextEdit.caretAfterExpansion(in: range, expansion: expansion), length: 0))
        return true
    }

    /// Tier 2: rewrite the whole value with the keyword replaced by the
    /// expansion, verified by read-back — the caret is only moved once the
    /// set is confirmed, so a read-only element that ignores the write can't
    /// send the backspace fallback erasing from the wrong position.
    private static func replaceValueViaAX(keyword: String, expansion: String) -> Bool {
        guard let probe = awaitTextProbe(keyword: keyword),
              let range = SnippetTextEdit.replacementRange(value: probe.value,
                                                           selectionStart: probe.selectionStart,
                                                           selectionLength: probe.selectionLength,
                                                           keyword: keyword) else { return false }
        let newValue = SnippetTextEdit.replacedValue(value: probe.value, range: range, expansion: expansion)
        guard AXUIElementSetAttributeValue(probe.element, kAXValueAttribute as CFString, newValue as CFTypeRef) == .success,
              Self.verifyApplied(element: probe.element, expected: newValue, insertLocation: range.location, expansion: expansion)
        else { return false }
        _ = setSelectedRange(of: probe.element, CFRange(location: SnippetTextEdit.caretAfterExpansion(in: range, expansion: expansion), length: 0))
        return true
    }

    /// Reads the value back until it shows the edit applied (some apps
    /// normalize on set, so exact equality alone would misread a success).
    /// Read-only elements can report success while ignoring the write —
    /// detecting that is what keeps the fallback path from double-inserting.
    private static func verifyApplied(element: AXUIElement, expected: String, insertLocation: Int, expansion: String) -> Bool {
        let deadline = Date().addingTimeInterval(0.1)
        while Date() < deadline {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let current = valueRef as? String,
               SnippetTextEdit.isApplied(current: current, expected: expected,
                                         insertLocation: insertLocation, expansion: expansion) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }

    /// Key-event erase: one backspace per typed character, then a beat for
    /// the app to process them before the insert.
    private func eraseWithBackspaces(_ count: Int) {
        for _ in 0..<count {
            sendKey(keyCode: 51, flags: [])
            Thread.sleep(forTimeInterval: Self.eraseInterval)
        }
        Thread.sleep(forTimeInterval: Self.phaseInterval)
    }

    /// Chromium-family paste: borrow the pasteboard, then trigger Edit →
    /// Paste via AX (Chromium web fields — browsers and Electron editors
    /// alike — accept the synthetic selection but drop a synthetic Cmd+V;
    /// the menu item goes through the app's real paste path). Falls back to
    /// a synthetic Cmd+V if the menu item can't be found or pressed.
    private func pasteViaChromiumMenu(_ resolved: String) {
        ClipboardMonitor.shared.suspendCapture()
        let saved = Self.savedPasteboardContent()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resolved, forType: .string)
        // Give the pasteboard write a moment to propagate before the app
        // reads it on paste.
        Thread.sleep(forTimeInterval: 0.025)
        if !Self.pasteViaEditMenu() {
            sendKey(keyCode: 9, flags: .maskCommand, source: pasteSource)
        }
        injectQueue.asyncAfter(deadline: .now() + Self.clipboardRestoreInterval) {
            Self.restorePasteboardContent(saved)
            ClipboardMonitor.shared.resumeCapture()
        }
    }

    /// Presses the Paste item of the frontmost app's Edit menu, located
    /// language-independently by its cmd-char "v" with command-only modifiers
    /// (excludes cmd+shift "Paste and Match Style"). Carbon cmdKey = 0x0100.
    private static func pasteViaEditMenu() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        let app = AXUIElementCreateApplication(pid)
        var menubarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menubarValue) == .success,
              let menubarValue,
              CFGetTypeID(menubarValue) == AXUIElementGetTypeID() else { return false }
        guard let menus = axChildren(of: menubarValue as! AXUIElement) else { return false }
        var fallback: AXUIElement?
        for menu in menus {
            guard let items = axChildren(of: menu) else { continue }
            for item in items {
                guard let cmdChar = axStringAttribute(of: item, kAXMenuItemCmdCharAttribute as CFString),
                      cmdChar.lowercased() == "v" else { continue }
                var modifiers = -1
                if let value = axNumberAttribute(of: item, kAXMenuItemCmdModifiersAttribute as CFString) {
                    modifiers = value
                }
                if modifiers == 0x0100 {
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
                if fallback == nil { fallback = item }
            }
        }
        if let fallback {
            return AXUIElementPerformAction(fallback, kAXPressAction as CFString) == .success
        }
        return false
    }

    private static func axChildren(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let value else { return nil }
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return [value as! AXUIElement]
        }
        guard CFGetTypeID(value) == CFArrayGetTypeID() else { return nil }
        return (value as! NSArray).compactMap { child in
            CFGetTypeID(child as CFTypeRef) == AXUIElementGetTypeID() ? (child as! AXUIElement) : nil
        }
    }

    private static func axStringAttribute(of element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private static func axNumberAttribute(of element: AXUIElement, _ attribute: CFString) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    /// Pasteboard + synthetic Cmd+V: borrows the clipboard for a moment and
    /// restores it once the paste has landed. Bracketed by
    /// ClipboardMonitor suspend/resume so neither the override nor the
    /// restore is captured into the history.
    private func paste(_ resolved: String) {
        ClipboardMonitor.shared.suspendCapture()
        let saved = Self.savedPasteboardContent()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resolved, forType: .string)
        // Give the pasteboard write a moment to propagate before the app
        // reads it on Cmd+V.
        Thread.sleep(forTimeInterval: 0.025)
        sendKey(keyCode: 9, flags: .maskCommand, source: pasteSource)

        injectQueue.asyncAfter(deadline: .now() + Self.clipboardRestoreInterval) {
            Self.restorePasteboardContent(saved)
            ClipboardMonitor.shared.resumeCapture()
        }
    }

    /// Saves every type currently on the general pasteboard so the override
    /// can be undone without losing non-text content (images, file URLs).
    private static func savedPasteboardContent() -> [(NSPasteboard.PasteboardType, Data)] {
        let pasteboard = NSPasteboard.general
        return (pasteboard.types ?? []).compactMap { type in
            guard let data = pasteboard.data(forType: type) else { return nil }
            return (type, data)
        }
    }

    private static func restorePasteboardContent(_ content: [(NSPasteboard.PasteboardType, Data)]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !content.isEmpty else { return }
        let item = NSPasteboardItem()
        for (type, data) in content {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
    }

    private func sendKey(keyCode: UInt16, flags: CGEventFlags, source: CGEventSource? = nil) {
        let eventSource = source ?? injectSource
        let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        keyDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: Self.keyPressInterval)

        let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        keyUp?.post(tap: .cghidEventTap)
    }
}
