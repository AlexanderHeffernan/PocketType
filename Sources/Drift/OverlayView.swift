import AppKit
import WebKit

@MainActor
private final class OverlayHeader: NSStackView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is NSButton { return hit }
            view = current.superview
        }
        return self
    }
}

/// The native controls surround Monkeytype's test and sign-in pages.
@MainActor
final class OverlayView: NSView {
    let browser: MonkeytypeBrowser
    let glassBackdrop = NSVisualEffectView()
    var onHide: (() -> Void)?
    private var practiceButton: NSButton!
    private var accountButton: NSButton!
    private var hideButton: NSButton!
    private var websiteInsets: [NSLayoutConstraint] = []

    init(frame: NSRect, browser: MonkeytypeBrowser) {
        self.browser = browser
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 28
        layer?.masksToBounds = true
        let title = NSTextField(labelWithString: "PocketType")
        title.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        title.textColor = NSColor(calibratedWhite: 0.9, alpha: 1)
        let logo = NSImageView(image: AppArtwork.overlayMark)
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.setAccessibilityLabel("PocketType logo")
        logo.widthAnchor.constraint(equalToConstant: 32).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 32).isActive = true
        practiceButton = button("Practice", action: #selector(practice))
        accountButton = button("Sign in", action: #selector(account))
        practiceButton.setAccessibilityIdentifier("practiceButton")
        accountButton.setAccessibilityIdentifier("accountButton")
        hideButton = button("", action: #selector(hide))
        hideButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Hide")
        hideButton.imagePosition = .imageTrailing
        hideButton.contentTintColor = .secondaryLabelColor
        hideButton.setAccessibilityIdentifier("hideButton")
        updateShortcut(KeyboardShortcut.standard.display)
        let header = OverlayHeader(views: [logo, title, NSView(), practiceButton, accountButton, hideButton])
        header.spacing = 16
        header.setCustomSpacing(8, after: logo)
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        let webView = browser.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        websiteInsets = [webView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                         trailingAnchor.constraint(equalTo: webView.trailingAnchor, constant: 14),
                         bottomAnchor.constraint(equalTo: webView.bottomAnchor, constant: 14)]
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 26),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -26),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            header.heightAnchor.constraint(equalToConstant: 32),
            webView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
        ] + websiteInsets)
        browser.onPageState = { [weak self] in self?.updateControls() }
        browser.onSurfaceChanged = { [weak self] in self?.updateSurface() }
        browser.onStatus = { message in
            let alert = NSAlert()
            alert.messageText = "PocketType"
            alert.informativeText = message
            alert.runModal()
        }
        updateControls()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.controlSize = .small
        return button
    }

    @objc private func practice() { browser.navigate(to: "https://monkeytype.com/") }
    @objc private func account() { browser.navigate(to: "https://monkeytype.com/login") }
    @objc private func hide() { onHide?() }

    func updateShortcut(_ display: String) {
        hideButton.title = "Hide  \(display)"
        hideButton.toolTip = "Show / hide · \(display) · change in Settings…"
        hideButton.setAccessibilityLabel("Hide PocketType, \(display)")
    }

    private func updateControls() {
        practiceButton.isHidden = browser.isPractice
        accountButton.isHidden = browser.isSignedIn != false
        updateSurface()
    }

    private func updateSurface() {
        let glass = browser.experimentalGlassEnabled && browser.isGlassPractice
        websiteInsets.forEach { $0.constant = glass ? 0 : 14 }
        browser.webView.layer?.cornerRadius = glass ? 0 : 16
        glassBackdrop.alphaValue = glass ? browser.glassBlur : 1
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if convert(event.locationInWindow, from: nil).y >= bounds.height - 50 {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let reducedTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 28, yRadius: 28)
        let glass = browser.experimentalGlassEnabled && browser.isGlassPractice
        let shade = reducedTransparency ? 1 : glass ? browser.glassTint : 0.40
        NSColor(calibratedRed: 9 / 255, green: 13 / 255, blue: 20 / 255, alpha: shade).setFill()
        shape.fill()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        if !reducedTransparency {
            NSGradient(starting: NSColor.white.withAlphaComponent(0.11), ending: .clear)?
                .draw(from: .zero, to: CGPoint(x: bounds.width * 0.60, y: bounds.height), options: [.drawsAfterEndingLocation])
        }
        let rim = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 28, yRadius: 28)
        rim.append(NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 27, yRadius: 27))
        rim.windingRule = .evenOdd
        rim.addClip()
        NSGradient(starting: NSColor.white.withAlphaComponent(0.48), ending: NSColor.white.withAlphaComponent(0.08))?
            .draw(from: .zero, to: CGPoint(x: bounds.width * 0.65, y: bounds.height), options: [.drawsAfterEndingLocation])
        NSGraphicsContext.restoreGraphicsState()
    }
}
