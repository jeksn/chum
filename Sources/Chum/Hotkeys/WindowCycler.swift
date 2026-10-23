import AppKit
import ApplicationServices
import Foundation

enum WindowCycler {
    /// Stable cycle order per app, keyed by CGWindowID. The AX window list is
    /// app-defined and for some apps follows z-order: the raised window moves
    /// to the front of the list, so "index of the main window + 1" picks the
    /// same second window every press and cycling degrades to toggling the
    /// top two windows of three or more. Freezing the order across presses
    /// (dropping closed windows, appending new ones) keeps a real
    /// round-robin. Main-thread only; cycleNext fires from the hotkey
    /// handler.
    private static var cycleOrder: [pid_t: [CGWindowID]] = [:]

    static func cycleNext() {
        guard Accessibility.isTrusted else {
            Accessibility.openSystemSettings()
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier

        let axApp = AXUIElementCreateApplication(pid)

        guard let windows = copyValue(axApp, for: kAXWindowsAttribute as CFString) as? [AXUIElement],
              windows.count > 1 else { return }

        let current = copyValue(axApp, for: kAXMainWindowAttribute as CFString) as! AXUIElement?

        let candidates = windows.map { window -> (window: AXUIElement, id: CGWindowID?) in
            (window, WindowManipulator.cgWindowID(of: window))
        }

        let nextWindow: AXUIElement?
        if let currentID = current.flatMap(WindowManipulator.cgWindowID(of:)),
           candidates.allSatisfy({ $0.id != nil }) {
            let ids = candidates.map(\.id!)

            var order = cycleOrder[pid] ?? []
            order = order.filter(ids.contains)
            for id in ids where !order.contains(id) { order.append(id) }
            cycleOrder[pid] = order

            let currentIndex = order.firstIndex(of: currentID) ?? 0
            let nextID = order[(currentIndex + 1) % order.count]
            nextWindow = candidates.first { $0.id == nextID }?.window
        } else {
            // Fallback when window IDs can't be resolved for every window:
            // the app-provided list order with CFEqual matching.
            let currentIndex: Int
            if let current {
                currentIndex = windows.firstIndex { CFEqual($0, current) } ?? 0
            } else {
                currentIndex = 0
            }
            let nextIndex = (currentIndex + 1) % windows.count
            nextWindow = windows[nextIndex]
        }

        guard let nextWindow else { return }
        AXUIElementSetAttributeValue(axApp, kAXMainWindowAttribute as CFString, nextWindow)
        AXUIElementPerformAction(nextWindow, kAXRaiseAction as CFString)
        app.activate(options: [.activateAllWindows])
    }

    private static func copyValue(_ element: AXUIElement, for attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute, &value)
        return value
    }
}
