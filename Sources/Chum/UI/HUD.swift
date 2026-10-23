import AppKit
import SwiftUI

final class HUD {
    static let shared = HUD()

    static func show(_ message: String) {
        shared.display(message)
    }

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    private func display(_ message: String) {
        let panel = ensurePanel()
        (panel.contentView as? NSHostingView<HUDView>)?.rootView = HUDView(message: message)
        position(panel)
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HUDView(message: ""))
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - panel.frame.width / 2
        let y = visible.maxY - visible.height * 0.12 - panel.frame.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct HUDView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }
}
