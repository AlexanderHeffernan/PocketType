import AppKit
import Combine
import Sparkle

/// Sparkle verifies the signed feed and archive, installs in place, and relaunches.
@MainActor
final class AppUpdates {
    private var controller: SPUStandardUpdaterController?
    private var observations = Set<AnyCancellable>()
    var onChange: (() -> Void)?
    var onWillCheck: (() -> Void)?

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }
    var automatic: Bool { controller?.updater.automaticallyChecksForUpdates ?? false }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }

    func start() {
        // Tests / swift run have no app metadata; only start inside the packaged app.
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] _ in self?.onChange?() }.store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).sink { [weak self] _ in self?.onChange?() }.store(in: &observations)
        controller.startUpdater()
    }

    func setAutomatic(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func check() {
        guard canCheck else { return }
        onWillCheck?()
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

@MainActor
final class UpdateSettingsView: NSStackView {
    private let updates: AppUpdates
    private let automatic = NSSwitch()
    private let check = NSButton(title: "Check for Updates…", target: nil, action: nil)

    init(updates: AppUpdates) {
        self.updates = updates
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 20
        let icon = NSImageView(image: AppArtwork.icon)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let name = NSTextField(labelWithString: "PocketType")
        name.font = .systemFont(ofSize: 19, weight: .semibold)
        let version = NSTextField(labelWithString: "Version \(updates.version)")
        version.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        version.textColor = .secondaryLabelColor
        let identity = NSStackView(views: [name, version])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 5
        let hero = NSStackView(views: [icon, identity])
        hero.alignment = .centerY
        hero.spacing = 14
        addArrangedSubview(hero)

        let label = NSTextField(labelWithString: "Check automatically")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        automatic.target = self
        automatic.action = #selector(toggleAutomatic)
        automatic.setAccessibilityLabel("Check for updates automatically")
        automatic.setAccessibilityIdentifier("automaticUpdateChecks")
        let row = NSStackView(views: [label, NSView(), automatic])
        row.alignment = .centerY
        let note = NSTextField(wrappingLabelWithString: "Checks about every six hours. You'll choose when to install and restart.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        check.target = self
        check.action = #selector(checkNow)
        check.bezelStyle = .rounded
        check.setAccessibilityIdentifier("checkForUpdates")
        let card = NSStackView(views: [row, note, check])
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 16
        card.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        addArrangedSubview(card)
        let trust = NSTextField(wrappingLabelWithString: "Updates are signed and verified by Sparkle before installation. Your preferences and Monkeytype session stay on this Mac.")
        trust.font = .systemFont(ofSize: 12)
        trust.textColor = .secondaryLabelColor
        addArrangedSubview(trust)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalTo: widthAnchor),
            row.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -32),
            note.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -32),
            trust.widthAnchor.constraint(equalTo: widthAnchor),
        ])
        updates.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func refresh() {
        automatic.state = updates.automatic ? .on : .off
        automatic.isEnabled = updates.version != "Development"
        check.isEnabled = updates.canCheck
    }

    @objc private func toggleAutomatic() { updates.setAutomatic(automatic.state == .on) }
    @objc private func checkNow() { updates.check() }
}
