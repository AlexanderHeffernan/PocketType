import AppKit
import WebKit
import Testing
@testable import Drift

@MainActor @Test func onlyOfficialHTTPSOriginsAreEmbedded() {
    for address in ["https://monkeytype.com/", "https://www.monkeytype.com/account"] {
        #expect(MonkeytypeBrowser.isMonkeytypeURL(URL(string: address)!))
    }
    for address in ["http://monkeytype.com", "https://monkeytype.com.evil.example", "https://evil.example/monkeytype.com", "https://monkeytype.com@evil.example", "file:///monkeytype.com"] {
        #expect(!MonkeytypeBrowser.isMonkeytypeURL(URL(string: address)!))
    }
}

@MainActor @Test func focusModeHidesChromeButKeepsTestsResultsAndNotices() async throws {
    _ = NSApplication.shared
    let browser = MonkeytypeBrowser(dataStore: .nonPersistent())
    let web = browser.webView
    web.loadHTMLString("""
        <html><head></head><body>
        <div class="fixed"><div class="content-grid" id="merch"><a href="https://mktp.co/merch">merch</a></div>
        <div class="content-grid" id="notice">Important account notice</div></div>
        <div id="app"><header id="nav">navigation</header>
        <mount data-component="header" id="mountedNav"><header>navigation</header></mount>
        <mount data-component="footer" id="mountedLinks"><footer>footer links</footer></mount>
        <main><div id="pageTest"><textarea id="wordsInput"></textarea><div id="words">type here</div></div>
        <div id="pageLogin"><input id="email" type="email"><input id="password" type="password"></div></main>
        <footer id="links">footer links</footer><div class="advertisement" id="ad">ad</div></div>
        <div role="dialog" id="consent">Cookie choices</div>
        </body></html>
        """, baseURL: URL(string: "https://monkeytype.com/login"))
    for _ in 0..<100 {
        if (try? await web.evaluateJavaScript("!!document.getElementById('drift-focus')")) as? Bool == true { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(try await web.evaluateJavaScript("!!document.getElementById('drift-focus')") as? Bool == true)
    for id in ["nav", "links", "mountedNav", "mountedLinks", "merch", "ad"] {
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('\(id)')).display") as? String == "none")
    }
    // Results mount later, after a completed test. The stylesheet must keep them
    // visible without hiding warnings, consent choices or the test's own input.
    _ = try await web.evaluateJavaScript("document.querySelector('main').insertAdjacentHTML('beforeend', '<div id=\"result\"><header id=\"stats\">72 WPM</header></div>')")
    for id in ["wordsInput", "words", "result", "stats", "notice", "consent", "email", "password"] {
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('\(id)')).display") as? String != "none")
    }
}

@MainActor @Test func reopeningDuringDismissalPreservesWebsite() async throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let defaults = UserDefaults.standard
    let oldLaunched = defaults.object(forKey: "hasLaunched")
    let oldFrame = defaults.object(forKey: "overlayFrame")
    defaults.set(true, forKey: "hasLaunched")
    defaults.removeObject(forKey: "overlayFrame")
    defer {
        defaults.set(oldLaunched, forKey: "hasLaunched")
        defaults.set(oldFrame, forKey: "overlayFrame")
    }
    let delegate = AppDelegate()
    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    let panel = try #require(app.windows.first { $0 is TypingPanel })
    defer {
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        panel.orderOut(nil)
    }
    let view = try #require(panel.contentView?.subviews.compactMap { $0 as? OverlayView }.first)
    let web = view.browser.webView
    web.stopLoading()
    web.navigationDelegate = nil // Local fixture; production embeds only the official HTTPS site.
    web.loadHTMLString("<html><body><input id='practice' value='unfinished test'></body></html>", baseURL: nil)
    for _ in 0..<100 {
        if (try? await web.evaluateJavaScript("!!document.getElementById('practice')")) as? Bool == true { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    delegate.toggle()
    delegate.toggle()
    delegate.toggle() // An old exit completion must not hide the reopened page.
    for _ in 0..<25 { try await Task.sleep(for: .milliseconds(30)) }
    #expect(panel.isVisible)
    #expect(panel.alphaValue == 1)
    #expect(panel.styleMask.contains(.resizable))
    #expect(try await web.evaluateJavaScript("document.getElementById('practice').value") as? String == "unfinished test")
    let screen = try #require(panel.screen).visibleFrame
    let customized = TypingPanel.fittedFrame(NSRect(x: screen.minX + 25, y: screen.minY + 45, width: 820, height: 460), in: screen)
    panel.setFrame(customized, display: true)
    delegate.toggle()
    for _ in 0..<15 { try await Task.sleep(for: .milliseconds(30)) }
    #expect(!panel.isVisible)
    delegate.toggle()
    try await Task.sleep(for: .milliseconds(400))
    #expect(panel.frame == customized)
    #expect(defaults.string(forKey: "overlayFrame").map(NSRectFromString) == customized)
    delegate.openSettings()
    #expect(panel.isVisible)
    let settings = try #require(app.windows.first { $0.windowController is ShortcutSettingsController })
    #expect(settings.isVisible)
    settings.close()
    #expect(panel.isVisible)
    delegate.resetOverlayFrame()
    try await Task.sleep(for: .milliseconds(400))
    #expect(panel.frame == TypingPanel.fittedFrame(nil, in: screen))
    #expect(try await web.evaluateJavaScript("document.getElementById('practice').value") as? String == "unfinished test")
}

@MainActor @Test func overlayFrameFitsChangedDisplaysAndLimits() {
    let screen = NSRect(x: -1920, y: 25, width: 1920, height: 1055)
    #expect(TypingPanel.fittedFrame(NSRect(x: -1850, y: 100, width: 900, height: 500), in: screen) == NSRect(x: -1850, y: 100, width: 900, height: 500))
    #expect(TypingPanel.fittedFrame(NSRect(x: 9000, y: -5000, width: 10, height: 20), in: screen) == NSRect(x: -776, y: 41, width: 760, height: 420))
    #expect(TypingPanel.fittedFrame(NSRect(x: -9000, y: 5000, width: 9000, height: 7000), in: screen) == NSRect(x: -1904, y: 64, width: 1600, height: 1000))
    #expect(TypingPanel.fittedFrame(nil, in: NSRect(x: 0, y: 0, width: 700, height: 400)) == NSRect(x: 16, y: 16, width: 668, height: 368))
}

@MainActor @Test func accountControlsFollowWebsiteStateAndSPARoutes() async throws {
    _ = NSApplication.shared
    let browser = MonkeytypeBrowser(dataStore: .nonPersistent())
    let overlay = OverlayView(frame: NSRect(x: 0, y: 0, width: 1060, height: 600), browser: browser)
    let buttons = try #require(overlay.subviews.compactMap { $0 as? NSStackView }.first).arrangedSubviews.compactMap { $0 as? NSButton }
    let account = try #require(buttons.first { $0.accessibilityIdentifier() == "accountButton" })
    let practice = try #require(buttons.first { $0.accessibilityIdentifier() == "practiceButton" })
    #expect(account.isHidden) // Unknown is not treated as signed out.
    browser.webView.loadHTMLString("<html><head></head><body class='loading'><header><a data-nav-item='login' href='/login'>login</a></header></body></html>", baseURL: URL(string: "https://monkeytype.com/"))
    for _ in 0..<100 {
        if (try? await browser.webView.evaluateJavaScript("!!document.getElementById('drift-focus')")) as? Bool == true { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    // A provisional guest control must not flash Sign in while restoring a session.
    try await Task.sleep(for: .milliseconds(600))
    #expect(browser.isSignedIn == nil && account.isHidden)
    _ = try await browser.webView.evaluateJavaScript("document.querySelector('header').innerHTML = '<a data-nav-item=account>account</a>'")
    try await Task.sleep(for: .milliseconds(600))
    #expect(browser.isSignedIn == nil && account.isHidden)
    _ = try await browser.webView.evaluateJavaScript("document.body.classList.remove('loading')")
    for _ in 0..<100 {
        if browser.isSignedIn == true { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(account.isHidden)
    // A genuine guest is shown once loading completes, too.
    _ = try await browser.webView.evaluateJavaScript("document.body.classList.add('loading'); document.querySelector('header').innerHTML = '<a data-nav-item=login>login</a>'")
    try await Task.sleep(for: .milliseconds(600))
    #expect(browser.isSignedIn == nil && account.isHidden)
    _ = try await browser.webView.evaluateJavaScript("document.body.classList.remove('loading')")
    for _ in 0..<100 {
        if browser.isSignedIn == false { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(!account.isHidden && account.title == "Sign in")
    #expect(practice.isHidden)
    _ = try await browser.webView.evaluateJavaScript("""
        history.pushState({}, '', '/account');
        document.querySelector('header').innerHTML = `<a data-nav-item="account">account</a><div data-ui-element="accountMenu"><button onclick="document.querySelector('header').innerHTML='<a data-nav-item=login>login</a>'"><i class="fa-sign-out-alt"></i>Sign out</button></div>`;
        """)
    for _ in 0..<100 {
        if browser.isSignedIn == true && !browser.isPractice { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(!practice.isHidden && account.isHidden)
    browser.signOut()
    for _ in 0..<100 {
        if browser.isSignedIn == false { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(account.title == "Sign in")
    _ = try await browser.webView.evaluateJavaScript("history.pushState({}, '', '/')")
    for _ in 0..<100 {
        if practice.isHidden { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(practice.isHidden)
}

@MainActor @Test func experimentalGlassRestoresThemeAndFallsBackWithoutLosingInput() async throws {
    _ = NSApplication.shared
    let suite = "MonkeytypeQuick.GlassTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let browser = MonkeytypeBrowser(dataStore: .nonPersistent(), defaults: defaults)
    let web = browser.webView
    web.frame = NSRect(x: 0, y: 0, width: 1060, height: 550)
    #expect(!browser.experimentalGlassEnabled)
    web.loadHTMLString("""
        <html><head><style>:root { --bg-color: #234567; --sub-color: #456789; overflow-y: scroll; }
        body { margin: 0; } #app { min-height: 900px; }
        body { background: var(--bg-color); } .customBackground { background: red; }
        .hidden { display: none; } #words { color: var(--sub-color); }
        #words.blurred { filter: blur(3px); }</style></head>
        <body><div class="customBackground"></div><div id="app"><main>
        <div data-ui-element="testConfig"><div class="card">time words</div></div>
        <div id="typingTest"><div id="wordsWrapper"><input id="practice" value="unfinished test">
        <div id="words" class="blurred">type here</div>
        <div id="focusWarning" class="pointer-events-none"><i class="fa-mouse-pointer"></i>Click to focus</div></div></div>
        <div id="result" class="hidden">72 WPM</div>
        </main></div><div role="dialog" id="notice">Important notice</div></body></html>
        """, baseURL: URL(string: "https://monkeytype.com/"))
    for _ in 0..<100 {
        if !web.isLoading, (try? await web.evaluateJavaScript("!!document.getElementById('drift-focus')")) as? Bool == true { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(try await web.evaluateJavaScript("getComputedStyle(document.documentElement).backgroundColor") as? String == "rgb(35, 69, 103)")
    browser.setExperimentalGlass(true)
    for _ in 0..<30 { try await Task.sleep(for: .milliseconds(20)) }
    if browser.experimentalGlassEnabled {
        #expect(defaults.bool(forKey: "experimentalGlass"))
        for selector in ["html", "body", "#app", "main"] {
            #expect(try await web.evaluateJavaScript("getComputedStyle(document.querySelector('\(selector)')).backgroundColor") as? String == "rgba(0, 0, 0, 0)")
        }
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.customBackground')).display") as? String == "none")
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('words')).color") as? String == "rgb(181, 189, 201)")
        browser.setAppearancePreview(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('words')).filter") as? String == "none")
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('focusWarning')).display") as? String == "none")
        browser.setAppearancePreview(false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('words')).filter") as? String == "blur(3px)")
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('focusWarning')).display") as? String != "none")
        browser.setGlassAppearance(tint: 0.73, controlsOpacity: 0.27, boostText: false, blur: 0.38)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.documentElement, '::before').content") as? String == "none")
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.documentElement).scrollbarWidth") as? String == "none")
        // Overflowing practice stays scrollable without WebKit's native gutter.
        #expect(try await web.evaluateJavaScript("document.documentElement.clientWidth === innerWidth && document.body.clientWidth === innerWidth") as? Bool == true)
        #expect(try await web.evaluateJavaScript("document.body.scrollTop = 120; document.body.scrollTop") as? Int == 120)
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.card')).backgroundColor") as? String == "rgba(17, 22, 30, 0.27)")
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('words')).color") as? String == "rgb(69, 103, 137)")
        let reopened = MonkeytypeBrowser(dataStore: .nonPersistent(), defaults: defaults)
        #expect(reopened.experimentalGlassEnabled)
        #expect(reopened.glassTint == 0.73 && reopened.glassControlsOpacity == 0.27 && reopened.glassBlur == 0.38 && !reopened.glassBoostText)
        for endpoint in [0.0, 1.0] {
            browser.setGlassAppearance(tint: endpoint, controlsOpacity: endpoint, boostText: true, blur: endpoint)
            let restored = MonkeytypeBrowser(dataStore: .nonPersistent(), defaults: defaults)
            #expect(restored.glassTint == endpoint && restored.glassControlsOpacity == endpoint && restored.glassBlur == endpoint)
        }
        // SPA navigation and completed results restore the normal canvas without disabling the preference.
        for route in ["/login", "/account", "/"] {
            _ = try await web.evaluateJavaScript("history.pushState({}, '', '\(route)')")
            try await Task.sleep(for: .milliseconds(650))
            #expect(try await web.evaluateJavaScript("getComputedStyle(document.documentElement).backgroundColor") as? String == (route == "/" ? "rgba(0, 0, 0, 0)" : "rgb(35, 69, 103)"))
            #expect(browser.experimentalGlassEnabled)
        }
        _ = try await web.evaluateJavaScript("document.getElementById('typingTest').classList.add('hidden'); document.getElementById('result').classList.remove('hidden')")
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.documentElement).backgroundColor") as? String == "rgb(35, 69, 103)")
        _ = try await web.evaluateJavaScript("document.getElementById('typingTest').classList.remove('hidden'); document.getElementById('result').classList.add('hidden')")
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.documentElement).backgroundColor") as? String == "rgba(0, 0, 0, 0)")
        browser.setExperimentalGlass(false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String == "rgb(35, 69, 103)")
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.documentElement).overflowY") as? String == "scroll")
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.customBackground')).display") as? String != "none")
        // Simulate a future site style that defeats our transparency override.
        _ = try await web.evaluateJavaScript("document.head.insertAdjacentHTML('beforeend', '<style>html.quick-glass #app > main { background: #123456 !important; }</style>')")
        browser.setExperimentalGlass(true)
        for _ in 0..<100 {
            if !browser.experimentalGlassEnabled { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(browser.glassStatus.contains("could not be applied"))
    } else {
        // Unsupported WebKit / Reduce Transparency must keep the normal page.
        #expect(browser.glassStatus.contains("normal background"))
    }
    #expect(!browser.experimentalGlassEnabled)
    #expect(!defaults.bool(forKey: "experimentalGlass"))
    #expect(try await web.evaluateJavaScript("getComputedStyle(document.documentElement).backgroundColor") as? String == "rgb(35, 69, 103)")
    #expect(try await web.evaluateJavaScript("document.getElementById('practice').value") as? String == "unfinished test")
    _ = try await web.evaluateJavaScript("document.getElementById('result').classList.remove('hidden')")
    for id in ["result", "notice"] {
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('\(id)')).display") as? String != "none")
    }
}
