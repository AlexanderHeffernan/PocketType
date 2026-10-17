import AppKit

@MainActor
enum AppArtwork {
    static let icon = NSImage(contentsOf: Bundle.module.url(forResource: "AppIcon", withExtension: "png")!)!
    static let overlayMark = NSImage(contentsOf: Bundle.module.url(forResource: "OverlayMark", withExtension: "png")!)!

    static let menuBarIcon: NSImage = {
        let image = NSImage(contentsOf: Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png")!)!
        image.size = NSSize(width: 24, height: 22)
        image.isTemplate = true
        image.accessibilityDescription = "PocketType"
        return image
    }()
}
