import AppKit

@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "About PocketType"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        let surface = NSVisualEffectView()
        surface.material = .hudWindow
        surface.blendingMode = .behindWindow
        surface.state = .active
        window.contentView = surface
        let tint = NSView(frame: surface.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(calibratedWhite: 0.055, alpha: 0.78).cgColor
        surface.addSubview(tint)

        let tile = NSImageView(image: AppArtwork.icon)
        tile.imageScaling = .scaleProportionallyUpOrDown
        tile.setAccessibilityLabel("PocketType logo")
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 64),
            tile.heightAnchor.constraint(equalToConstant: 64),
        ])
        let title = NSTextField(labelWithString: "PocketType")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        let identity = NSStackView(views: [title, versionLabel])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 5
        let hero = NSStackView(views: [tile, identity])
        hero.alignment = .centerY
        hero.spacing = 16

        let tagline = NSTextField(labelWithString: "Monkeytype, a shortcut away.")
        tagline.font = .systemFont(ofSize: 16, weight: .medium)
        let description = NSTextField(wrappingLabelWithString: "A shortcut-driven macOS companion for Monkeytype.")
        description.font = .systemFont(ofSize: 13)
        description.textColor = .secondaryLabelColor
        let caption = NSTextField(labelWithString: "Independent companion")
        caption.font = .systemFont(ofSize: 12, weight: .semibold)
        let attribution = NSTextField(wrappingLabelWithString: "Not affiliated with or endorsed by Monkeytype.")
        let licence = NSTextField(wrappingLabelWithString: "PocketType is GPL-3.0-only. Monkeytype is a separate GPL-3.0 project by Miodec and its contributors. Its website is loaded remotely.")
        for label in [attribution, licence] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
        }
        let card = NSStackView(views: [caption, attribution, licence])
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 12
        card.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        for label in [attribution, licence] {
            label.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -32).isActive = true
        }

        let website = NSButton(title: "Monkeytype", target: self, action: #selector(openWebsite))
        let source = NSButton(title: "Monkeytype source", target: self, action: #selector(openSource))
        website.toolTip = "Open monkeytype.com"
        source.toolTip = "Open Monkeytype’s upstream source and licence on GitHub"
        for button in [website, source] {
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12)
            button.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)
            button.image?.size = NSSize(width: 10, height: 10)
            button.imagePosition = .imageTrailing
            button.imageHugsTitle = true
        }
        let links = NSStackView(views: [website, source])
        links.spacing = 10
        links.distribution = .fillEqually
        let stack = NSStackView(views: [hero, tagline, description, card, links])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.setCustomSpacing(8, after: tagline)
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: surface.bottomAnchor, constant: -24),
            description.widthAnchor.constraint(equalTo: stack.widthAnchor),
            card.widthAnchor.constraint(equalTo: stack.widthAnchor),
            links.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func openWebsite() { NSWorkspace.shared.open(URL(string: "https://monkeytype.com/")!) }
    @objc private func openSource() { NSWorkspace.shared.open(URL(string: "https://github.com/monkeytypegame/monkeytype")!) }
}
