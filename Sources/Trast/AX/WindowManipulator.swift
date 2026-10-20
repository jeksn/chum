import AppKit
import ApplicationServices
import Darwin

struct WindowRef {
    let pid: pid_t
    let app: AXUIElement
    let window: AXUIElement
    let windowID: CGWindowID?
    let title: String?

    var restoreKey: String {
        if let windowID { return "cg:\(windowID)" }
        return "fb:\(pid)-\(title ?? "untitled")"
    }
}

enum WindowManipulator {
    private static let getWindowID: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY) else { return nil }
        guard let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()

    static func frontmostWindow() -> WindowRef? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        return window(ofProcess: app.processIdentifier)
    }

    static func lastActiveNonSelfWindow() -> WindowRef? {
        let ourPID = ProcessInfo.processInfo.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int else { continue }
            if ownerPID == Int(ourPID) { continue }
            if let window = window(ofProcess: pid_t(ownerPID)) {
                return window
            }
        }

        return nil
    }

    static func window(ofProcess pid: pid_t) -> WindowRef? {
        let app = AXUIElementCreateApplication(pid)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &result)
        guard error == .success, let window = result else { return nil }
        return makeRef(pid: pid, app: app, window: window as! AXUIElement)
    }

    /// CGWindowID backing an AX window element, or nil when the private
    /// accessor is unavailable. This is the only reliable window identity
    /// across separate AX queries — CFEqual on freshly fetched element refs
    /// is not guaranteed to match, and app-provided window lists reorder
    /// (some follow z-order), so index-based comparisons break.
    static func cgWindowID(of window: AXUIElement) -> CGWindowID? {
        guard let getWindowID else { return nil }
        var id = CGWindowID(0)
        guard getWindowID(window, &id) == .success else { return nil }
        return id
    }

    private static func makeRef(pid: pid_t, app: AXUIElement, window: AXUIElement) -> WindowRef {
        let windowID = cgWindowID(of: window)

        var title: String?
        var titleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success {
            title = titleValue as? String
        }

        return WindowRef(pid: pid, app: app, window: window, windowID: windowID, title: title)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let position = positionValue,
            let size = sizeValue
        else { return nil }

        var point = CGPoint.zero
        var cgSize = CGSize.zero
        guard
            AXValueGetValue(position as! AXValue, .cgPoint, &point),
            AXValueGetValue(size as! AXValue, .cgSize, &cgSize)
        else { return nil }

        return CGRect(origin: cocoaOrigin(fromAXTopLeft: point, height: cgSize.height), size: cgSize)
    }

    /// Outcome of setting a window frame: `.applied` when the app ended up at
    /// the requested frame, `.adjusted` when the AX sets succeeded but the
    /// app kept a different frame (usually its minimum window size), and
    /// `.failed` on an AX error.
    enum FrameSetResult {
        case applied
        case adjusted
        case failed(AXError)
    }

    @discardableResult
    static func setFrame(_ ref: WindowRef, to frame: CGRect) -> FrameSetResult {
        var lastSetError: AXError?
        for _ in 0..<5 {
            lastSetError = applyFrame(ref, to: frame)
            if lastSetError == nil, let current = Self.frame(of: ref.window), isClose(current, frame) {
                return .applied
            }
            usleep(60_000)
        }
        if let lastSetError { return .failed(lastSetError) }
        return .adjusted
    }

    private static func applyFrame(_ ref: WindowRef, to frame: CGRect) -> AXError? {
        var size = CGSize(width: frame.width, height: frame.height)
        var point = axTopLeft(fromCocoaOrigin: frame.origin, height: frame.height)
        guard
            let sizeValue = AXValueCreate(.cgSize, &size),
            let pointValue = AXValueCreate(.cgPoint, &point)
        else { return .failure }

        let sizeError = AXUIElementSetAttributeValue(ref.window, kAXSizeAttribute as CFString, sizeValue)
        guard sizeError == .success else { return sizeError }

        let positionError = AXUIElementSetAttributeValue(ref.window, kAXPositionAttribute as CFString, pointValue)
        guard positionError == .success else { return positionError }
        return nil
    }

    private static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 1
            && abs(a.minY - b.minY) <= 1
            && abs(a.width - b.width) <= 1
            && abs(a.height - b.height) <= 1
    }

    static func screen(containing frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return screen
        }

        let best = NSScreen.screens
            .compactMap { screen -> (NSScreen, CGFloat)? in
                let intersection = screen.frame.intersection(frame)
                guard !intersection.isNull else { return nil }
                return (screen, intersection.width * intersection.height)
            }
            .max { $0.1 < $1.1 }
        return best?.0 ?? NSScreen.main
    }

    static func cocoaOrigin(fromAXTopLeft point: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y - height)
    }

    static func axTopLeft(fromCocoaOrigin origin: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: origin.x, y: primaryScreenHeight - origin.y - height)
    }

    private static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }
}
