import AppKit
import Carbon

@MainActor
final class TypingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onClose: (() -> Void)?

    override func performClose(_ sender: Any?) { onClose?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Handle the native close command before the embedded website consumes it.
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func performDrag(with event: NSEvent) {
        let initial = frame.origin
        let start = convertPoint(toScreen: event.locationInWindow)
        while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                         until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { break }
            let point = convertPoint(toScreen: next.locationInWindow)
            setFrameOrigin(NSPoint(x: initial.x + point.x - start.x, y: initial.y + point.y - start.y))
        }
    }

    static func fittedFrame(_ saved: NSRect?, in screen: NSRect) -> NSRect {
        let available = screen.insetBy(dx: 16, dy: 16)
        let maximum = NSSize(width: min(1600, available.width), height: min(1000, available.height))
        let minimum = NSSize(width: min(760, maximum.width), height: min(420, maximum.height))
        let size = NSSize(width: min(maximum.width, max(minimum.width, saved?.width ?? 1060)),
                          height: min(maximum.height, max(minimum.height, saved?.height ?? 600)))
        let origin = saved?.origin ?? NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        return NSRect(x: min(max(available.minX, origin.x), available.maxX - size.width),
                      y: min(max(available.minY, origin.y), available.maxY - size.height),
                      width: size.width, height: size.height)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var panel: TypingPanel!
    private var overlay: OverlayView!
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var previousApp: NSRunningApplication?
    private let browser = MonkeytypeBrowser()
    private var hotKeyAvailable = false
    private var isDismissing = false
    private var isPresenting = false
    private var presentationID = 0
    private var shortcut = KeyboardShortcut.load()
    private var shortcutEnabled = !UserDefaults.standard.bool(forKey: "toggleShortcutDisabled")
    private var settings: ShortcutSettingsController?
    private var about: AboutWindowController?
    private let updates = AppUpdates()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppArtwork.icon
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatus()
        overlay = OverlayView(frame: NSRect(x: 0, y: 0, width: 1060, height: 600), browser: browser)
        overlay.onHide = { [weak self] in self?.finish(restoreFocus: true) }
        let glass = overlay.glassBackdrop
        glass.frame = overlay.bounds
        glass.autoresizingMask = [.width, .height]
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 28
        glass.layer?.masksToBounds = true
        let mask = NSImage(size: NSSize(width: 57, height: 57), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        mask.resizingMode = .stretch
        glass.maskImage = mask
        let surface = NSView(frame: overlay.bounds)
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 28
        surface.layer?.masksToBounds = true
        surface.addSubview(glass)
        overlay.autoresizingMask = [.width, .height]
        surface.addSubview(overlay)
        panel = TypingPanel(contentRect: overlay.bounds, styleMask: [.borderless, .closable, .resizable], backing: .buffered, defer: false)
        panel.contentView = surface
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.title = "PocketType"
        panel.onClose = { [weak self] in self?.finish(restoreFocus: true) }
        registerHotKey()
        overlay.updateShortcut(shortcutEnabled ? shortcut.display : nil)
        updates.onWillCheck = { [weak self] in
            self?.settings?.window?.orderOut(nil)
            self?.finish(restoreFocus: false)
        }
        updates.start()
        rebuildMenu()
        browser.navigate(to: "https://monkeytype.com/")
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            show()
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "PocketType")
        let about = appMenu.addItem(withTitle: "About PocketType", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        let preferences = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        preferences.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PocketType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        // Nil targets route these standard commands to WebKit's focused field.
        // Do not read the clipboard or inject text; the website owns paste policy.
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                     ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func registerHotKey() {
        var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard identifier.signature == 0x44524654 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().toggle()
            }
            return noErr
        }, 1, &specification, context, &eventHandler)
        registerCurrentShortcut()
    }

    private func registerCurrentShortcut() {
        guard shortcutEnabled, hotKey == nil else { return }
        let identifier = EventHotKeyID(signature: 0x44524654, id: 1)
        hotKeyAvailable = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
                                             GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    private func changeShortcut(_ value: KeyboardShortcut) -> Bool {
        if value == shortcut, hotKey != nil { return true }
        // Register first so a conflict cannot discard the working shortcut.
        var replacement: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x44524654, id: 1)
        if shortcutEnabled {
            guard RegisterEventHotKey(value.keyCode, value.modifiers, identifier,
                                      GetApplicationEventTarget(), 0, &replacement) == noErr else { return false }
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        hotKeyAvailable = replacement != nil
        shortcut = value
        value.save()
        overlay.updateShortcut(shortcutEnabled ? value.display : nil)
        updateStatus()
        rebuildMenu()
        return true
    }

    private func setShortcutEnabled(_ enabled: Bool) -> Bool {
        shortcutEnabled = enabled
        if enabled {
            registerCurrentShortcut()
            if !hotKeyAvailable {
                shortcutEnabled = false
                return false
            }
        } else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            hotKeyAvailable = false
        }
        UserDefaults.standard.set(!enabled, forKey: "toggleShortcutDisabled")
        overlay.updateShortcut(enabled ? shortcut.display : nil)
        updateStatus()
        rebuildMenu()
        return true
    }

    @objc func toggle() {
        if panel.isVisible && !isDismissing { finish(restoreFocus: true) } else { show() }
    }

    private func show() {
        settings?.recorder.cancelRecording()
        presentationID += 1
        let showingID = presentationID
        isPresenting = true
        isDismissing = false
        panel.ignoresMouseEvents = false
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        let saved = UserDefaults.standard.string(forKey: "overlayFrame").map(NSRectFromString)
        let screen = saved.flatMap { frame in
            NSScreen.screens.filter { $0.visibleFrame.intersects(frame) }.max {
                let a = $0.visibleFrame.intersection(frame), b = $1.visibleFrame.intersection(frame)
                return a.width * a.height < b.width * b.height
            }
        } ?? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.maxSize = NSSize(width: min(1600, frame.width - 32), height: min(1000, frame.height - 32))
            panel.minSize = NSSize(width: min(760, panel.maxSize.width), height: min(420, panel.maxSize.height))
            panel.setFrame(TypingPanel.fittedFrame(saved, in: frame), display: false)
        }
        let destination = panel.frame
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        if !reducedMotion { panel.setFrameOrigin(NSPoint(x: destination.minX, y: destination.minY - 14)) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(browser.webView)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducedMotion ? 0.12 : 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(destination, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.presentationID == showingID else { return }
                self.isPresenting = false
                self.rememberFrame()
            }
        }
    }

    private func rememberFrame() {
        guard panel.isVisible, !isDismissing, !isPresenting else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "overlayFrame")
    }

    func windowDidMove(_ notification: Notification) { rememberFrame() }
    func windowDidResize(_ notification: Notification) { rememberFrame() }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let frame = panel.screen?.visibleFrame else { return }
        panel.maxSize = NSSize(width: min(1600, frame.width - 32), height: min(1000, frame.height - 32))
        panel.minSize = NSSize(width: min(760, panel.maxSize.width), height: min(420, panel.maxSize.height))
    }

    @objc func resetOverlayFrame() {
        UserDefaults.standard.removeObject(forKey: "overlayFrame")
        show()
    }

    private func finish(restoreFocus: Bool) {
        guard panel.isVisible, !isDismissing else { return }
        rememberFrame()
        settings?.recorder.cancelRecording()
        settings?.window?.orderOut(nil)
        isDismissing = true
        isPresenting = false
        presentationID += 1
        let closingID = presentationID
        let appToRestore = restoreFocus ? previousApp : nil
        previousApp = nil
        panel.makeFirstResponder(nil)
        panel.ignoresMouseEvents = true
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let destination = panel.frame.offsetBy(dx: 0, dy: reducedMotion ? 0 : -8)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducedMotion ? 0.10 : 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(destination, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.presentationID == closingID else { return }
                self.panel.orderOut(nil)
                self.isDismissing = false
                if let appToRestore, NSApp.isActive,
                   appToRestore.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    appToRestore.activate()
                }
            }
        }
    }

    func applicationDidResignActive(_ notification: Notification) { finish(restoreFocus: false) }

    private func updateStatus() {
        guard let button = statusItem.button else { return }
        button.image = AppArtwork.menuBarIcon
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.title = ""
        button.toolTip = shortcutEnabled ? "PocketType · \(shortcut.display) to show / hide" : "PocketType · click to show / hide"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let show = NSMenuItem(title: "Show / hide PocketType" + (shortcutEnabled ? "  ·  \(shortcut.display)" : ""), action: #selector(toggle), keyEquivalent: "")
        show.target = self
        show.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(show)
        menu.addItem(.separator())
        for (title, action, symbol) in [("Settings…", #selector(openSettings), "gearshape"),
                                         ("Check for Updates…", #selector(checkForUpdates), "arrow.triangle.2.circlepath"),
                                         ("Reset overlay size & position", #selector(resetOverlayFrame), "arrow.counterclockwise"),
                                         ("Account", #selector(openAccount), "person.crop.circle"),
                                         ("Open MonkeyType", #selector(openInBrowser), "globe"),
                                         ("About PocketType", #selector(openAbout), "info.circle")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        let signOutItem = menu.addItem(withTitle: "Sign out", action: #selector(signOut), keyEquivalent: "")
        signOutItem.target = self
        signOutItem.image = NSImage(systemSymbolName: "rectangle.portrait.and.arrow.right", accessibilityDescription: nil)
        if shortcutEnabled && !hotKeyAvailable {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Shortcut unavailable — another app may be using it.", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PocketType", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)
        for item in menu.items {
            item.image?.size = NSSize(width: 16, height: 16)
            item.image?.isTemplate = true
        }
        menuWillOpen(menu)
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(openAccount) }?.title = browser.isSignedIn == false ? "Sign in" : "Account"
        menu.items.first { $0.action == #selector(signOut) }?.isHidden = browser.isSignedIn != true
    }

    @objc private func signOut() { browser.signOut() }

    @objc private func checkForUpdates() { updates.check() }

    @objc func openAbout() {
        finish(restoreFocus: false)
        NSApp.activate(ignoringOtherApps: true)
        if about == nil { about = AboutWindowController() }
        about?.showWindow(nil)
        about?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        finish(restoreFocus: false)
        NSApp.terminate(nil)
    }

    @objc func openSettings() {
        if !panel.isVisible || isDismissing { show() }
        if settings == nil {
            let controller = ShortcutSettingsController(shortcut: shortcut, shortcutEnabled: shortcutEnabled, browser: browser, updates: updates)
            controller.onSave = { [weak self] in self?.changeShortcut($0) ?? false }
            controller.onSetShortcutEnabled = { [weak self] in self?.setShortcutEnabled($0) ?? false }
            controller.recorder.onRecordingChanged = { [weak self] recording in
                guard let self else { return }
                if recording {
                    if let hotKey = self.hotKey { UnregisterEventHotKey(hotKey) }
                    self.hotKey = nil
                } else {
                    self.registerCurrentShortcut()
                    self.rebuildMenu()
                }
            }
            settings = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window = settings?.window, let screen = panel.screen?.visibleFrame {
            let right = panel.frame.maxX + 12
            let left = panel.frame.minX - window.frame.width - 12
            let x = right + window.frame.width <= screen.maxX ? right : left >= screen.minX ? left : screen.maxX - window.frame.width - 16
            let y = min(max(screen.minY + 16, panel.frame.maxY - window.frame.height), screen.maxY - window.frame.height - 16)
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccount() {
        if !panel.isVisible || isDismissing { show() }
        browser.navigate(to: browser.isSignedIn == true ? "https://monkeytype.com/account" : "https://monkeytype.com/login")
    }

    @objc private func openInBrowser() { NSWorkspace.shared.open(URL(string: "https://monkeytype.com/")!) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible || isDismissing { show() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        finish(restoreFocus: false)
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

@main
struct PocketTypeApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--smoke-test") {
            precondition(AppArtwork.icon.isValid && AppArtwork.overlayMark.isValid && AppArtwork.menuBarIcon.isTemplate)
            print("PocketType packaged launch smoke test passed (resources and Sparkle loaded)")
            return
        }
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
