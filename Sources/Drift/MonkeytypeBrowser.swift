import AppKit
import WebKit
import WebKitBackground

@MainActor
private final class PageStateHandler: NSObject, WKScriptMessageHandler {
    weak var browser: MonkeytypeBrowser?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url, MonkeytypeBrowser.isMonkeytypeURL(url),
              let state = message.body as? [String: Any], let practice = state["practice"] as? Bool else { return }
        browser?.isPractice = practice
        browser?.isSignedIn = state["signedIn"] as? Bool
        if let glassPractice = state["glassPractice"] as? Bool, browser?.isGlassPractice != glassPractice {
            browser?.isGlassPractice = glassPractice
            browser?.applyGlassToDocument()
        }
        browser?.onPageState?()
    }
}

@MainActor
final class MonkeytypeBrowser: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var onStatus: ((String) -> Void)?
    var onPageState: (() -> Void)?
    fileprivate(set) var isSignedIn: Bool?
    fileprivate(set) var isPractice = true
    fileprivate(set) var isGlassPractice = false
    private let defaults: UserDefaults
    private var appearanceRevision = 0
    private var appearancePreview = false
    private(set) var experimentalGlassEnabled = false
    private(set) var glassTint = 0.55
    private(set) var glassControlsOpacity = 0.45
    private(set) var glassBlur = 1.0
    private(set) var glassBoostText = true
    private(set) var glassStatus = "Off · uses Monkeytype’s normal background."
    var onAppearanceChanged: (() -> Void)?
    var onSurfaceChanged: (() -> Void)?

    init(dataStore: WKWebsiteDataStore = .default(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let stateHandler = PageStateHandler()
        configuration.userContentController.add(stateHandler, contentWorld: .defaultClient, name: "pageState")
        // Observe only public DOM controls, never credentials or session storage.
        configuration.userContentController.addUserScript(WKUserScript(source: """
            if (location.protocol === 'https:' && ['monkeytype.com', 'www.monkeytype.com'].includes(location.hostname)) {
                let previous = '';
                function update() {
                    const account = document.querySelector('header [data-nav-item="account"]');
                    const login = document.querySelector('header [data-nav-item="login"]');
                    // The guest header mounts before saved authentication is restored.
                    // Monkeytype clears body.loading after auth and account data settle.
                    const ready = document.body && !document.body.classList.contains('loading');
                    const visible = element => element && !element.closest('.hidden') && getComputedStyle(element).display !== 'none';
                    const glassPractice = location.pathname === '/' && !!visible(document.getElementById('typingTest')) && !visible(document.getElementById('result'));
                    const state = {practice: location.pathname === '/', glassPractice, signedIn: ready ? (account ? true : login ? false : null) : null};
                    const next = JSON.stringify(state);
                    if (next !== previous) { previous = next; window.webkit.messageHandlers.pageState.postMessage(state); }
                }
                new MutationObserver(update).observe(document.documentElement, {subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'href', 'style']});
                addEventListener('popstate', update);
                // Also cover history changes that don't mutate the DOM.
                setInterval(update, 500);
                update();
            }
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        configuration.userContentController.addUserScript(WKUserScript(source: """
            if (location.protocol === 'https:' &&
                ['monkeytype.com', 'www.monkeytype.com'].includes(location.hostname)) {
                const style = document.createElement('style');
                style.id = 'drift-focus';
                style.textContent = `
                    html { background-color: var(--bg-color, #323437) !important; }
                    html.quick-glass, html.quick-glass body,
                    html.quick-glass #app, html.quick-glass #app > main {
                        background: transparent !important;
                    }
                    html.quick-glass, html.quick-glass body {
                        transition: none !important;
                        scrollbar-width: none !important;
                        scrollbar-gutter: auto !important;
                    }
                    /* WebKit reserves a native gutter for the site's forced root
                       scrollbar even with scrollbar-width:none. Scroll inside the
                       body instead, so short windows still reach all content. */
                    html.quick-glass { overflow: hidden !important; }
                    html.quick-glass body {
                        height: 100vh !important;
                        overflow-y: auto !important;
                    }
                    html.quick-glass::-webkit-scrollbar,
                    html.quick-glass body::-webkit-scrollbar {
                        display: none !important;
                        width: 0 !important;
                        height: 0 !important;
                    }
                    html.quick-glass .customBackground { display: none !important; }
                    html.quick-glass [data-ui-element="testConfig"] .card {
                        background: linear-gradient(135deg, #ffffff0d, #ffffff02),
                            rgba(17, 22, 30, var(--quick-glass-controls, 0.45)) !important;
                        backdrop-filter: blur(16px) saturate(120%);
                        -webkit-backdrop-filter: blur(16px) saturate(120%);
                        box-shadow: inset 0 0 0 1px #ffffff18, 0 4px 16px #00000014;
                    }
                    html.quick-glass.quick-glass-readable #typingTest,
                    html.quick-glass.quick-glass-readable [data-ui-element="testConfig"] {
                        --sub-color: #b5bdc9;
                        --text-color: #f3f6fc;
                        --error-color: #ff7f91;
                        --error-extra-color: #ff9aad;
                        text-shadow: 0 1px 3px #000000b3;
                    }
                    html.quick-glass.quick-glass-readable #caret {
                        background-color: #f3f6fc !important;
                    }
                    html.quick-glass.quick-preview #words.blurred {
                        filter: none !important;
                        opacity: 1 !important;
                    }
                    html.quick-glass.quick-preview #wordsWrapper .pointer-events-none:has(.fa-mouse-pointer) {
                        display: none !important;
                    }
                    #app > header, #app > footer,
                    #app > mount[data-component="header"],
                    #app > mount[data-component="footer"],
                    #app .advertisement,
                    #result .advertisement,
                    .fixed > .content-grid:has(a[href="https://mktp.co/merch"]),
                    .fixed > .content-grid:has(a[href="https://monkeytype.store"]),
                    .fixed > .content-grid:has(a[href="https://monkeytype.store/"]) {
                        display: none !important;
                    }
                    #app {
                        grid-template-rows: 1fr !important;
                        row-gap: 0 !important;
                        padding-bottom: 1.5rem !important;
                    }
                `;
                document.head.appendChild(style);
                // Keep login/account links in this persistent WebKit session;
                // other non-test pages still belong in the regular browser.
                document.addEventListener('click', event => {
                    const link = event.target.closest?.('a[href]');
                    if (!link) return;
                    const url = new URL(link.href, location.href);
                    if (url.origin === location.origin && !['/', '/login', '/account'].includes(url.pathname)) {
                        event.preventDefault();
                        event.stopImmediatePropagation();
                        window.open(url.href, '_blank', 'noopener');
                    }
                }, true);
            }
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        defaults.register(defaults: ["glassTint": 0.55, "glassControlsOpacity": 0.45, "glassBlur": 1.0, "glassBoostText": true])
        glassTint = min(1, max(0, defaults.double(forKey: "glassTint")))
        glassControlsOpacity = min(1, max(0, defaults.double(forKey: "glassControlsOpacity")))
        glassBlur = min(1, max(0, defaults.double(forKey: "glassBlur")))
        glassBoostText = defaults.bool(forKey: "glassBoostText")
        stateHandler.browser = self
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 16
        webView.layer?.masksToBounds = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        if defaults.bool(forKey: "experimentalGlass") { setExperimentalGlass(true) }
    }

    func setExperimentalGlass(_ enabled: Bool) {
        if enabled {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
                fallBackToNormal("Reduce Transparency is enabled in macOS.")
                return
            }
            guard MTSetTransparentBackground(webView, true) else {
                fallBackToNormal("This WebKit version does not support transparent backgrounds.")
                return
            }
        } else if experimentalGlassEnabled {
            _ = MTSetTransparentBackground(webView, false)
        }
        appearanceRevision += 1
        experimentalGlassEnabled = enabled
        defaults.set(enabled, forKey: "experimentalGlass")
        webView.underPageBackgroundColor = enabled ? .clear : NSColor(calibratedWhite: 0.2, alpha: 1)
        glassStatus = enabled ? "On · practice only. Other screens keep their theme background." : "Off · uses Monkeytype’s normal background."
        onAppearanceChanged?()
        onSurfaceChanged?()
        applyGlassToDocument()
    }

    func setGlassAppearance(tint: Double, controlsOpacity: Double, boostText: Bool, blur: Double = 1) {
        glassTint = min(1, max(0, tint))
        glassControlsOpacity = min(1, max(0, controlsOpacity))
        glassBlur = min(1, max(0, blur))
        glassBoostText = boostText
        defaults.set(glassTint, forKey: "glassTint")
        defaults.set(glassControlsOpacity, forKey: "glassControlsOpacity")
        defaults.set(glassBlur, forKey: "glassBlur")
        defaults.set(glassBoostText, forKey: "glassBoostText")
        appearanceRevision += 1
        applyGlassToDocument()
        onAppearanceChanged?()
        onSurfaceChanged?()
    }

    func setAppearancePreview(_ enabled: Bool) {
        appearancePreview = enabled
        applyGlassToDocument()
    }

    fileprivate func applyGlassToDocument() {
        guard let url = webView.url, Self.isMonkeytypeURL(url), !webView.isLoading else { return }
        appearanceRevision += 1
        let enabled = experimentalGlassEnabled && isGlassPractice
        let revision = appearanceRevision
        webView.evaluateJavaScript("""
            (() => {
                if (!document.getElementById('drift-focus')) return false;
                const root = document.documentElement;
                root.style.setProperty('--quick-glass-controls', '\(glassControlsOpacity)');
                root.classList.toggle('quick-glass-readable', \(glassBoostText));
                root.classList.toggle('quick-preview', \(appearancePreview));
                root.classList.toggle('quick-glass', \(enabled));
                if (!\(enabled)) return true;
                return [root, document.body, document.getElementById('app'), document.querySelector('#app > main')].filter(Boolean)
                    .every(element => {
                        const style = getComputedStyle(element);
                        return style.backgroundColor === 'rgba(0, 0, 0, 0)' && style.backgroundImage === 'none';
                    });
            })()
            """) { [weak self] result, error in
                guard let self, self.appearanceRevision == revision, enabled else { return }
                if error != nil || result as? Bool != true {
                    self.fallBackToNormal("The website’s transparent background could not be applied.")
                }
            }
    }

    private func fallBackToNormal(_ reason: String) {
        appearanceRevision += 1
        _ = MTSetTransparentBackground(webView, false)
        experimentalGlassEnabled = false
        defaults.set(false, forKey: "experimentalGlass")
        webView.underPageBackgroundColor = NSColor(calibratedWhite: 0.2, alpha: 1)
        webView.evaluateJavaScript("document.documentElement.classList.remove('quick-glass')", completionHandler: nil)
        glassStatus = "\(reason) Using the normal background; experiment turned off."
        onAppearanceChanged?()
        onSurfaceChanged?()
    }

    @objc private func accessibilityChanged() {
        if experimentalGlassEnabled && NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            fallBackToNormal("Reduce Transparency was enabled in macOS.")
        }
    }

    static func isMonkeytypeURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && ["monkeytype.com", "www.monkeytype.com"].contains(url.host?.lowercased())
    }

    func navigate(to address: String) {
        guard let url = URL(string: address), Self.isMonkeytypeURL(url) else { return }
        webView.load(URLRequest(url: url))
    }

    func signOut() {
        guard let url = webView.url, Self.isMonkeytypeURL(url) else { return }
        webView.evaluateJavaScript("""
            (() => {
                const button = [...document.querySelectorAll('header [data-ui-element="accountMenu"] button')]
                    .find(button => button.querySelector('.fa-sign-out-alt'));
                if (!button) return false;
                button.click();
                return true;
            })()
            """) { [weak self] result, error in
                if error != nil || result as? Bool != true {
                    self?.onStatus?("Monkeytype’s sign-out control is unavailable. Open Sign in / account from the menu and try again.")
                }
            }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        // Subframes remain under the site's own security policy (e.g. CAPTCHA and Firebase).
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
        } else if Self.isMonkeytypeURL(url) && ["", "/", "/login", "/account"].contains(url.path) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated && ["https", "http", "mailto"].contains(url.scheme) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        appearanceRevision += 1
        isSignedIn = nil
        onPageState?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyGlassToDocument()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error, in: webView)
    }

    private func report(_ error: Error, in webView: WKWebView) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        onStatus?("Couldn’t load \(webView.url?.host ?? "Monkeytype"): \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if experimentalGlassEnabled { fallBackToNormal("The website process stopped while glass was enabled.") }
        webView.reload()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url,
              ["https", "http", "mailto"].contains(url.scheme) else { return nil }
        if Self.isMonkeytypeURL(url) && ["/login", "/account"].contains(url.path) {
            navigate(to: url.absoluteString)
            return nil
        }
        NSWorkspace.shared.open(url)
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let alert = NSAlert()
        alert.messageText = webView.url?.host ?? "Monkeytype"
        alert.informativeText = message
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = webView.url?.host ?? "Monkeytype"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}
