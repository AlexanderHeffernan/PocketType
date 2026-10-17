import AppKit
import Carbon

struct KeyboardShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let standard = KeyboardShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), keyLabel: "Space")

    var display: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃+" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥+" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧+" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘+" }
        return symbols + keyLabel
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty,
              let characters = event.characters(byApplyingModifiers: []), !characters.isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        modifiers = carbon
        switch Int(event.keyCode) {
        case kVK_Space: keyLabel = "Space"
        case kVK_Tab: keyLabel = "Tab"
        case kVK_Return: keyLabel = "Return"
        case kVK_Delete: keyLabel = "Delete"
        case kVK_ForwardDelete: keyLabel = "Forward Delete"
        case kVK_LeftArrow: keyLabel = "←"
        case kVK_RightArrow: keyLabel = "→"
        case kVK_UpArrow: keyLabel = "↑"
        case kVK_DownArrow: keyLabel = "↓"
        default:
            if let scalar = characters.unicodeScalars.first, (0xF704...0xF717).contains(scalar.value) {
                keyLabel = "F\(scalar.value - 0xF704 + 1)"
            } else {
                keyLabel = characters.uppercased()
            }
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> KeyboardShortcut {
        guard let saved = defaults.dictionary(forKey: "toggleShortcut"),
              let keyCode = saved["keyCode"] as? UInt32,
              let modifiers = saved["modifiers"] as? UInt32,
              let keyLabel = saved["keyLabel"] as? String else { return .standard }
        return KeyboardShortcut(keyCode: keyCode, modifiers: modifiers, keyLabel: keyLabel)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(["keyCode": keyCode, "modifiers": modifiers, "keyLabel": keyLabel], forKey: "toggleShortcut")
    }
}

@MainActor
final class ShortcutRecorder: NSButton {
    var onCapture: ((KeyboardShortcut) -> Bool)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onMessage: ((String) -> Void)?
    private(set) var shortcut: KeyboardShortcut
    private(set) var isRecording = false

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        title = shortcut.display
        target = self
        action = #selector(startRecording)
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        setAccessibilityLabel("Show or hide keyboard shortcut")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        guard !isRecording else { cancelRecording(); return }
        guard window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        title = "Press shortcut…"
        onMessage?("Press your shortcut. Escape cancels.")
        onRecordingChanged?(true)
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        title = shortcut.display
        onMessage?("")
        onRecordingChanged?(false)
    }

    func updateShortcut(_ value: KeyboardShortcut) {
        shortcut = value
        title = value.display
    }

    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == UInt16(kVK_Escape) { cancelRecording(); return }
        guard !event.isARepeat else { return }
        guard let value = KeyboardShortcut(event: event) else {
            onMessage?("Include Option, Control or Command with a key.")
            return
        }
        let saved = onCapture?(value) == true
        if saved {
            updateShortcut(value)
        }
        cancelRecording()
        onMessage?(saved ? "Shortcut saved." : "That shortcut is unavailable. Your previous shortcut is unchanged.")
    }
}

@MainActor
final class ShortcutSettingsController: NSWindowController, NSWindowDelegate {
    let recorder: ShortcutRecorder
    private let shortcutToggle = NSSwitch()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let browser: MonkeytypeBrowser
    private let glassToggle = NSSwitch()
    private let glassMessage = NSTextField(wrappingLabelWithString: "")
    private let tintSlider = NSSlider(value: 0.55, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let controlsSlider = NSSlider(value: 0.45, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let blurSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let tintValue = NSTextField(labelWithString: "")
    private let controlsValue = NSTextField(labelWithString: "")
    private let blurValue = NSTextField(labelWithString: "")
    private let boostText = NSButton(checkboxWithTitle: "Improve text contrast", target: nil, action: nil)
    private let sections = NSSegmentedControl(labels: ["Appearance", "Updates"], trackingMode: .selectOne, target: nil, action: nil)
    private var appearanceStack: NSStackView!
    private var updateStack: UpdateSettingsView!
    var onSave: ((KeyboardShortcut) -> Bool)?
    var onSetShortcutEnabled: ((Bool) -> Bool)?

    init(shortcut: KeyboardShortcut, shortcutEnabled: Bool, browser: MonkeytypeBrowser, updates: AppUpdates) {
        self.browser = browser
        recorder = ShortcutRecorder(shortcut: shortcut)
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 560),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "PocketType Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.delegate = self
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
        sections.selectedSegment = 0
        sections.target = self
        sections.action = #selector(changeSection)
        sections.setAccessibilityIdentifier("settingsSections")
        sections.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(sections)
        let subtitle = NSTextField(labelWithString: "PocketType")
        subtitle.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        let logo = NSImageView(image: AppArtwork.icon)
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.setAccessibilityLabel("PocketType logo")
        logo.widthAnchor.constraint(equalToConstant: 24).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let brand = NSStackView(views: [logo, subtitle])
        brand.alignment = .centerY
        brand.spacing = 8
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        message.setAccessibilityIdentifier("shortcutMessage")
        let reset = NSButton(image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset shortcut")!, target: self, action: #selector(restoreDefault))
        reset.bezelStyle = .rounded
        reset.toolTip = "Restore \(KeyboardShortcut.standard.display)"
        recorder.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        recorder.toolTip = "Click, then press a shortcut with Option, Control or Command. Escape cancels."
        let shortcutLabel = NSTextField(labelWithString: "Shortcut")
        shortcutLabel.font = .systemFont(ofSize: 12, weight: .medium)
        shortcutToggle.state = shortcutEnabled ? .on : .off
        shortcutToggle.target = self
        shortcutToggle.action = #selector(toggleShortcut)
        shortcutToggle.setAccessibilityIdentifier("toggleShortcutEnabled")
        shortcutToggle.setAccessibilityLabel("Enable global shortcut")
        shortcutToggle.toolTip = "Enable the global show / hide shortcut. Menu-bar access and ⌘W work when disabled."
        let shortcutRow = NSStackView(views: [shortcutLabel, NSView(), recorder, reset, shortcutToggle])
        shortcutRow.alignment = .centerY
        shortcutRow.spacing = 8
        glassToggle.target = self
        glassToggle.action = #selector(toggleGlass)
        glassToggle.setAccessibilityIdentifier("experimentalGlassToggle")
        glassToggle.setAccessibilityLabel("Experimental glass background")
        let glassLabel = NSTextField(labelWithString: "Glass")
        glassLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let info = NSButton(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About experimental glass")!, target: nil, action: nil)
        info.isBordered = false
        info.contentTintColor = .secondaryLabelColor
        info.toolTip = "Experimental WebKit transparency for practice. Restores the normal background if a failure is detected."
        let glassRow = NSStackView(views: [glassLabel, info, NSView(), glassToggle])
        glassRow.alignment = .centerY
        glassRow.spacing = 8
        glassMessage.font = .systemFont(ofSize: 12)
        glassMessage.textColor = .secondaryLabelColor
        glassMessage.setAccessibilityIdentifier("experimentalGlassStatus")
        func sliderRow(_ title: String, slider: NSSlider, value: NSTextField) -> NSStackView {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            value.alignment = .right
            value.widthAnchor.constraint(equalToConstant: 36).isActive = true
            let heading = NSStackView(views: [label, NSView(), value])
            heading.alignment = .centerY
            slider.target = self
            slider.action = #selector(changeGlassAppearance)
            slider.isContinuous = true
            slider.setAccessibilityLabel(title)
            slider.setAccessibilityIdentifier(title == "Background shade" ? "glassTintSlider" : title == "Blur" ? "glassBlurSlider" : "glassControlsSlider")
            let row = NSStackView(views: [heading, slider])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 6
            heading.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            slider.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            return row
        }
        let tintRow = sliderRow("Background shade", slider: tintSlider, value: tintValue)
        let controlsRow = sliderRow("Control opacity", slider: controlsSlider, value: controlsValue)
        let blurRow = sliderRow("Blur", slider: blurSlider, value: blurValue)
        blurSlider.toolTip = "Blend from a clear backdrop to macOS’s full frosted-glass effect."
        boostText.target = self
        boostText.action = #selector(changeGlassAppearance)
        boostText.font = .systemFont(ofSize: 12)
        let resetGlass = NSButton(title: "Reset glass appearance", target: self, action: #selector(resetGlassAppearance))
        resetGlass.bezelStyle = .rounded
        let card = NSStackView(views: [glassRow, blurRow, tintRow, controlsRow, boostText])
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 20
        card.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        for row in [glassRow, blurRow, tintRow, controlsRow] {
            row.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -32).isActive = true
        }
        let stack = NSStackView(views: [brand, card, shortcutRow, message, resetGlass, glassMessage])
        appearanceStack = stack
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(12, after: brand)
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        updateStack = UpdateSettingsView(updates: updates)
        updateStack.translatesAutoresizingMaskIntoConstraints = false
        updateStack.isHidden = true
        surface.addSubview(updateStack)
        NSLayoutConstraint.activate([
            sections.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            sections.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            sections.topAnchor.constraint(equalTo: surface.topAnchor, constant: 40),
            sections.heightAnchor.constraint(equalToConstant: 26),
            updateStack.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            updateStack.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            updateStack.topAnchor.constraint(equalTo: stack.topAnchor),
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: sections.bottomAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: surface.bottomAnchor, constant: -16),
            card.widthAnchor.constraint(equalTo: stack.widthAnchor),
            shortcutRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor),
            glassMessage.widthAnchor.constraint(equalTo: stack.widthAnchor),
            resetGlass.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])
        recorder.onMessage = { [weak self] text in
            self?.message.stringValue = text
            self?.message.isHidden = text.isEmpty
        }
        message.isHidden = true
        recorder.onCapture = { [weak self] in self?.onSave?($0) ?? false }
        browser.onAppearanceChanged = { [weak self] in self?.updateGlassControls() }
        updateGlassControls()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func selectUpdates() {
        sections.selectedSegment = 1
        changeSection()
    }

    @objc private func changeSection() {
        recorder.cancelRecording()
        appearanceStack.isHidden = sections.selectedSegment != 0
        updateStack.isHidden = sections.selectedSegment != 1
        browser.setAppearancePreview(window?.isKeyWindow == true && sections.selectedSegment == 0)
    }

    @objc private func toggleGlass() {
        recorder.cancelRecording()
        browser.setExperimentalGlass(glassToggle.state == .on)
    }

    @objc private func toggleShortcut() {
        recorder.cancelRecording()
        let enabled = shortcutToggle.state == .on
        let saved = onSetShortcutEnabled?(enabled) == true
        if !saved { shortcutToggle.state = enabled ? .off : .on }
        message.isHidden = false
        message.stringValue = saved
            ? (enabled ? "Shortcut enabled." : "Shortcut disabled. Open PocketType from the menu bar.")
            : "That shortcut is unavailable. The shortcut remains disabled."
    }

    private func updateGlassControls() {
        glassToggle.state = browser.experimentalGlassEnabled ? .on : .off
        glassMessage.stringValue = browser.glassStatus
        glassMessage.isHidden = !browser.glassStatus.contains("experiment turned off")
        tintSlider.doubleValue = browser.glassTint
        controlsSlider.doubleValue = browser.glassControlsOpacity
        blurSlider.doubleValue = browser.glassBlur
        tintValue.stringValue = "\(Int((browser.glassTint * 100).rounded()))%"
        controlsValue.stringValue = "\(Int((browser.glassControlsOpacity * 100).rounded()))%"
        blurValue.stringValue = "\(Int((browser.glassBlur * 100).rounded()))%"
        boostText.state = browser.glassBoostText ? .on : .off
        for control: NSControl in [tintSlider, controlsSlider, blurSlider, boostText] {
            control.isEnabled = browser.experimentalGlassEnabled
        }
    }

    @objc private func changeGlassAppearance() {
        browser.setGlassAppearance(tint: tintSlider.doubleValue, controlsOpacity: controlsSlider.doubleValue,
                                   boostText: boostText.state == .on, blur: blurSlider.doubleValue)
    }

    @objc private func resetGlassAppearance() {
        browser.setGlassAppearance(tint: 0.55, controlsOpacity: 0.45, boostText: true)
    }

    @objc private func restoreDefault() {
        recorder.cancelRecording()
        message.isHidden = false
        if onSave?(.standard) == true {
            recorder.updateShortcut(.standard)
            message.stringValue = "Default shortcut restored."
        } else {
            message.stringValue = "Option–Space is unavailable. Your shortcut is unchanged."
        }
    }

    func windowDidBecomeKey(_ notification: Notification) { browser.setAppearancePreview(sections.selectedSegment == 0) }
    func windowDidResignKey(_ notification: Notification) {
        recorder.cancelRecording()
        browser.setAppearancePreview(false)
    }
    func windowWillClose(_ notification: Notification) {
        recorder.cancelRecording()
        browser.setAppearancePreview(false)
    }
}
