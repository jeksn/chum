import AppKit

enum StatusBarIcon {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            let targetHeight: CGFloat = 18
            if image.size.height > 0 {
                let scale = targetHeight / image.size.height
                image.size = NSSize(width: image.size.width * scale, height: targetHeight)
            }
            return image
        }

        let fallback = NSImage(
            systemSymbolName: "rectangle.split.3x3",
            accessibilityDescription: "Chum"
        ) ?? NSImage()
        return fallback
    }()
}
