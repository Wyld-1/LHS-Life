//
//  EmbeddedWebState.swift
//  LHS Life
//
//  Generic web view state + view for Lunch, PowerSchool, and Schoology.
//  Mobile user agent forces responsive mobile layout on all sites.
//

import SwiftUI
internal import WebKit
internal import os

// MARK: - Navigation Delegate

final class EmbeddedWebDelegate: NSObject, WKNavigationDelegate {
    weak var state: EmbeddedWebState?

    func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.state?.isLoading = true
            self?.state?.loadError = nil
        }
    }
    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.state?.isLoading = false
            self?.state?.isReady = true
            self?.state?.canGoBack = webView.canGoBack
            // Inject email on Microsoft login page
            self?.state?.injectEmailIfNeeded(into: webView)
        }
    }
    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError e: Error) {
        Task { @MainActor [weak self] in
            self?.state?.isLoading = false
            // Still "ready" on failure — otherwise one bad network request
            // would leave launchProgress permanently short of 1.0 and hang
            // the LaunchScreen forever.
            self?.state?.isReady = true
            self?.state?.loadError = e
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError e: Error) {
        Task { @MainActor [weak self] in
            self?.state?.isLoading = false
            self?.state?.isReady = true
            self?.state?.loadError = e
        }
    }
}

// MARK: - Web State

@Observable
final class EmbeddedWebState {

    var isLoading = false
    var loadError: Error? = nil
    var isReady   = false
    var canGoBack = false

    private(set) var webView: WKWebView? = nil
    private let delegate = EmbeddedWebDelegate()

    let url: URL
    let siteName: String
    let injectDarkCSS: Bool

    init(url: URL, siteName: String, injectDarkCSS: Bool = false) {
        self.url           = url
        self.siteName      = siteName
        self.injectDarkCSS = injectDarkCSS
        delegate.state     = self
    }

    // iPhone Mobile Safari user agent — forces mobile/responsive layout on all sites.
    // Schoology and PowerSchool serve desktop HTML when the view identifies as iPad/Mac.
    private static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private static let darkStyleID = "ls-dark-override"

    private static let darkModeCSS = """
        body, div, p, span, td, th, label, input, select, textarea, a {
            color: #FFFFFF !important;
            background-color: transparent !important;
        }
        body { background-color: #13161C !important; }
        input, select, textarea, button {
            background-color: #1C2029 !important;
            border-color: #4A5168 !important;
            color: #FFFFFF !important;
        }
        a { color: #3A6FD8 !important; }
        """

    // Style element carries an ID so it can be found and removed later —
    // needed for live reactivity (Sunrise/Sunset auto-appearance switching
    // mid-session), not just a one-time injection at page load.
    private static let injectionScript = """
        (function() {
            if (document.getElementById('\(darkStyleID)')) return;
            var style = document.createElement('style');
            style.id = '\(darkStyleID)';
            style.textContent = `\(darkModeCSS)`;
            document.head.appendChild(style);
        })();
        """

    private static let removalScript = """
        (function() {
            var el = document.getElementById('\(darkStyleID)');
            if (el) el.remove();
        })();
        """

    private static func userScript(isDark: Bool) -> WKUserScript {
        WKUserScript(
            source: isDark ? injectionScript : removalScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }

    private static let darkWebBackground  = UIColor(red: 0.074, green: 0.086, blue: 0.11, alpha: 1)
    private static let lightWebBackground = UIColor(red: 0.949, green: 0.953, blue: 0.969, alpha: 1)

    @MainActor
    func initialize() {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        let isDark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        if injectDarkCSS && isDark {
            config.userContentController.addUserScript(Self.userScript(isDark: true))
        }
        let wv = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        wv.customUserAgent = Self.mobileUserAgent
        // Matches the app canvas in whichever mode is actually active —
        // previously hardcoded dark for all three sites (Lunch, PowerSchool,
        // Schoology), which would flash dark during load even in light mode.
        wv.backgroundColor = isDark ? Self.darkWebBackground : Self.lightWebBackground
        wv.scrollView.backgroundColor = .clear
        wv.isOpaque = true
        wv.scrollView.contentInsetAdjustmentBehavior = .always
        wv.navigationDelegate = delegate
        // NOTE: translatesAutoresizingMaskIntoConstraints is deliberately left at
        // its UIKit default (true) — see makeUIView. Setting it to false zeroes
        // the frame the instant it's applied (confirmed on device), which made
        // the first page load into a 0×0 viewport.
        webView = wv
        Self.applyObscuredInsets(to: wv)
        isLoading = true
        wv.load(URLRequest(url: url))
    }

    /// Called from EmbeddedWebView when SwiftUI's \.colorScheme actually
    /// changes while the app is running — covers Sunrise/Sunset
    /// auto-appearance, not just a fixed value read once at launch.
    /// Updates the already-loaded page immediately via JS, and swaps the
    /// WKUserScript so a future reload/navigation stays consistent too.
    @MainActor
    func updateAppearance(isDark: Bool) {
        guard let wv = webView else { return }
        wv.backgroundColor = isDark ? Self.darkWebBackground : Self.lightWebBackground
        guard injectDarkCSS else { return }
        wv.configuration.userContentController.removeAllUserScripts()
        wv.configuration.userContentController.addUserScript(Self.userScript(isDark: isDark))
        let script = isDark ? Self.injectionScript : Self.removalScript
        wv.evaluateJavaScript(script) { _, error in
            if let error {
                print("[EmbeddedWebState] appearance update JS error: \(error)")
            }
        }
    }

    /// The height of app chrome covering the top of the web view.
    ///
    /// iPhone: the floating toolbar overlays the content, so the web view must
    /// know that band is obscured.
    /// iPad: the NavigationSplitView detail column already lays the web view out
    /// BELOW its nav bar — nothing overlaps it — so the inset is zero. Applying
    /// the iPhone value there was what created the dead scroll band at the top of
    /// the iPad detail pane.
    private static var topObscuredInset: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 0 : LS.contentTopInset
    }

    /// Tells WebKit which part of the view is covered by app chrome, using the
    /// framework's own mechanism instead of scrollView.contentInset.
    ///
    /// WHY NOT contentInset: WKWebView derives its layout viewport from its
    /// FRAME and ignores scrollView.contentInset entirely. Setting contentInset
    /// therefore creates a region WebKit doesn't know about — its contentSize
    /// stays inflated by exactly the inset height, which is the dead band you can
    /// scroll into on iPad, and its notion of "scrolled to top" (offset 0)
    /// permanently disagrees with ours (offset -inset). Every correction site we
    /// had — applyInsets, correctScrollPosition's double-fire, the updateUIView
    /// re-snap — existed to paper over that disagreement after the fact, and none
    /// could win, because WebKit re-derives position from its own model on every
    /// reflow.
    ///
    /// obscuredContentInsets (iOS 26+) adjusts the layout viewport itself, so
    /// WebKit positions content correctly from first layout and keeps it correct
    /// across reflows, rotation and scroll restoration. Content still scrolls
    /// visually behind the toolbar; there is simply no phantom scrollable space.
    /// setMinimumViewportInset/maximumViewportInset (iOS 16+) is the older
    /// spelling of the same idea for the pre-26 LegacyTabDock path.
    @MainActor
    static func applyObscuredInsets(to wv: WKWebView) {
        let top = topObscuredInset
        let insets = UIEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        if #available(iOS 26, *) {
            wv.obscuredContentInsets = insets
        } else {
            wv.setMinimumViewportInset(insets, maximumViewportInset: insets)
        }
        // Scroll indicators are separate — obscuredContentInsets governs content
        // layout, not indicator geometry, so the bar would otherwise run under
        // the toolbar.
        wv.scrollView.verticalScrollIndicatorInsets = insets
    }

    @MainActor
    func refreshObscuredInsets() {
        guard let wv = webView else { return }
        Self.applyObscuredInsets(to: wv)
    }

    @MainActor
    func reload() {
        guard let wv = webView else { return }
        loadError = nil
        isLoading = true
        wv.load(URLRequest(url: url))
    }

    // MARK: - Microsoft email autofill

    /// Detects the Microsoft login page and injects the stored school email,
    /// then clicks Next so iOS Keychain can offer the saved password.
    @MainActor
    func injectEmailIfNeeded(into webView: WKWebView) {
        guard let host = webView.url?.host,
              host.contains("login.microsoftonline.com") || host.contains("login.microsoft.com")
        else { return }

        let email = UserSettings.shared.schoolEmail
        guard !email.isEmpty else { return }

        // Small delay so the page's own JS has finished rendering the input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let js = """
                (function() {
                    var input = document.querySelector('input[type="email"], input[name="loginfmt"], #i0116');
                    if (input) {
                        var nativeInput = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
                        nativeInput.set.call(input, '\(email)');
                        input.dispatchEvent(new Event('input', { bubbles: true }));
                        input.dispatchEvent(new Event('change', { bubbles: true }));
                        // Click Next after a short delay
                        setTimeout(function() {
                            var next = document.querySelector('#idSIButton9, input[type="submit"], button[type="submit"]');
                            if (next) next.click();
                        }, 300);
                    }
                })();
            """
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("[Autofill] JS error: \(error)")
                }
            }
        }
    }
}

// MARK: - View

struct EmbeddedWebView: View {
    @Bindable var webState: EmbeddedWebState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if let wv = webState.webView {
                    WebViewRepresentable(webView: wv, size: geo.size)
                        .ignoresSafeArea(edges: [.top, .bottom])
                        .onAppear {
                            // Insets are set once in initialize(), before load(),
                            // and owned by WebKit thereafter. Re-applied here only
                            // to cover an idiom change across a remount (iPad
                            // multitasking); it is idempotent, not a correction.
                            webState.refreshObscuredInsets()
                            // Tabs that aren't currently selected get fully
                            // unmounted by the native TabView/NavigationSplitView
                            // switch — not just hidden — so .onChange(of:
                            // colorScheme) below never fires for them while
                            // backgrounded, and remounting doesn't retroactively
                            // trigger .onChange either (it only fires on an
                            // actual change, not initial appearance). Re-check
                            // on every appear so a backgrounded tab catches up
                            // the moment you switch to it, not just live ones.
                            webState.updateAppearance(isDark: colorScheme == .dark)
                        }
                }

                if webState.isLoading || !webState.isReady {
                    Color.lsBackground.ignoresSafeArea(edges: [.top, .bottom])
                    ProgressView()
                        .tint(Color.lsBlue)
                        .scaleEffect(1.3)
                        // The enclosing ZStack is alignment: .top, which pinned
                        // this to the top edge — and since the web view ignores
                        // the top safe area, that edge is above the visible area
                        // entirely. Filling the space centers it instead of
                        // inheriting the stack's top alignment.
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let error = webState.loadError {
                    Color.lsBackground.ignoresSafeArea(edges: [.top, .bottom])
                    VStack(spacing: LS.md) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.lsSecondary)
                        Text("Couldn't load \(webState.siteName)")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsPrimary)
                        Text(error.localizedDescription)
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, LS.xl)
                        Button("Try Again") { webState.reload() }
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsBlue)
                    }
                    // Same top-alignment problem as the spinner above — the
                    // error state was pinned off-screen too, just less often seen.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

            }
        }
        .background(Color.lsBackground)
        .ignoresSafeArea(edges: [.top, .bottom])
        .animation(.lsFade, value: webState.isLoading)
        .animation(.lsFade, value: webState.isReady)
        .onChange(of: colorScheme) { _, newValue in
            webState.updateAppearance(isDark: newValue == .dark)
        }
    }
}

// MARK: - UIViewRepresentable

struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    let size: CGSize

    func makeUIView(context: Context) -> WKWebView {
        // translatesAutoresizingMaskIntoConstraints is deliberately left at its
        // UIKit default (true). Setting it to false zeroes the frame the instant
        // it's applied — confirmed on device: the web view loaded its entire
        // first page into a 0×0 viewport, then jumped to real size on first
        // mount, forcing WebKit to reflow the whole document out-of-process.
        //
        // The reason the flag was originally added — sizing to iPad's narrower
        // NavigationSplitView detail column instead of full screen — is already
        // covered by updateUIView below, which assigns frame explicitly from
        // GeometryReader's size on every layout.
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard size.width > 0, size.height > 0 else { return }
        let target = CGRect(origin: .zero, size: size)
        if uiView.frame != target {
            uiView.frame = target
        }
    }
}
