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
            self?.state?.correctScrollPosition(in: webView)
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
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.navigationDelegate = delegate
        // Created with an explicit frame (UIKit default leaves
        // translatesAutoresizingMaskIntoConstraints = true), but this view
        // gets embedded into SwiftUI via UIViewRepresentable, which sizes it
        // through Auto Layout constraints generated from .frame(). Leaving
        // the autoresizing-mask translation on creates two competing sizing
        // systems — the view keeps rendering at its original full-screen
        // frame regardless of the actual space SwiftUI gives it (e.g. the
        // narrower NavigationSplitView detail column when the iPad sidebar
        // is expanded). Turning this off lets SwiftUI's constraints fully
        // own sizing.
        // NOTE: translatesAutoresizingMaskIntoConstraints is deliberately NOT
        // turned off here — see makeUIView, which flips it at the moment SwiftUI
        // actually takes over sizing. Turning it off at this point discarded the
        // explicit UIScreen.main.bounds frame above: the view isn't in any
        // SwiftUI hierarchy yet during preload, so with the flag off and no
        // constraints to satisfy, Auto Layout sized it to 0×0 — and load() below
        // then rendered the entire first page into a zero-width viewport. Tapping
        // the tab later jumped the frame 0×0 -> real size, forcing WebKit to
        // reflow the whole document out-of-process, and scroll position does not
        // survive that reflow (no synchronous correction can, since the reflow
        // lands after the SwiftUI update pass). Keeping the real frame through
        // preload means the page lays out at the right width from the first byte;
        // on iPhone the eventual SwiftUI size equals UIScreen.main.bounds, so
        // there is no resize and no reflow at all.
        webView = wv
        // Content insets are applied HERE, before load() fires — not deferred to
        // EmbeddedWebView.onAppear. A tab the user hasn't opened yet has never
        // appeared, so onAppear has never run, so contentInset.top was still 0
        // for the whole first load: the network fetch, didFinish,
        // correctScrollPosition (which computes -contentInset.top, i.e. -0, a
        // no-op), and WebKit's own initial layout all settled against a zero
        // inset. The inset only became 124 when the tab was finally tapped —
        // after everything had already come to rest — leaving content parked one
        // inset-height too high, behind the floating header. Every later visit
        // was consistent because the inset was already correct by then. That
        // asymmetry was the whole bug. LS.contentTopInset is a constant known
        // at init, so there is no reason to learn it late.
        let initialInsets = UIEdgeInsets(top: LS.contentTopInset, left: 0, bottom: 0, right: 0)
        wv.scrollView.contentInset = initialInsets
        wv.scrollView.verticalScrollIndicatorInsets = initialInsets
        wv.scrollView.contentOffset = CGPoint(x: 0, y: -LS.contentTopInset)
        LHSLogger.webview.notice("\(self.siteName, privacy: .public) initialize — inset.top set to \(LS.contentTopInset, privacy: .public) before load()")
        isLoading = true
        wv.load(URLRequest(url: url))
        // isReady is deliberately NOT set here. It used to flip true the
        // instant this function created the WKWebView object — before
        // wv.load() had even started fetching, let alone rendered or
        // settled scroll position. LaunchScreen's launchProgress reads
        // exactly this flag to decide when preloading is actually done, so
        // that made the whole preload gate a no-op: all three tabs hit
        // isReady=true within the same run loop .task kicks them off in,
        // the loading screen dismissed almost instantly, and a genuinely
        // not-yet-loaded tab was fully reachable. isReady now only flips in
        // didFinish/didFail below, once there's an actual page (or a
        // confirmed failure) to show.
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

    @MainActor
    func applyInsets(top: CGFloat, bottom: CGFloat) {
        guard let wv = webView else { return }
        let insets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        wv.scrollView.contentInset = insets
        wv.scrollView.verticalScrollIndicatorInsets = insets
        // Setting contentInset doesn't retroactively move an already-settled
        // contentOffset to match it. initialize() (and the page load/scroll
        // settling that follows it) can happen before this tab has ever been
        // visually appeared-to, while contentInset.top was still 0 — so by
        // the time a real inset is applied here, the content is already
        // sitting at what's now the wrong resting point, shifted down by
        // exactly `top` points, hiding whatever sits in that band behind the
        // floating header. Re-snap every time insets are (re-)applied, since
        // that's the actual recurring moment that matters (every tab
        // appearance), not the one-time page-load event. Guarded so this
        // never fights a genuine in-progress user scroll further down the page.
        if wv.scrollView.contentOffset.y > -top {
            wv.scrollView.setContentOffset(CGPoint(x: 0, y: -top), animated: false)
        }
    }

    /// After navigation completes, some pages (notably Microsoft's login
    /// flow re-rendering with a validation error) auto-scroll to bring the
    /// erroring field into view, using the page's own script/focus behavior.
    /// That resets contentOffset to native (0, 0) rather than the actual
    /// "scrolled all the way to top" resting point our own top contentInset
    /// requires — (0, -contentInset.top) — since the page has no idea our
    /// inset exists. That gap is exactly inset-tall, hiding whatever sits in
    /// that band (the Microsoft/Schoology logo) behind the floating header.
    /// Correcting twice — immediately and after a short delay — since the
    /// page's own auto-scroll can fire slightly after didFinish rather than
    /// exactly at it.
    @MainActor
    func correctScrollPosition(in webView: WKWebView) {
        let target = CGPoint(x: 0, y: -webView.scrollView.contentInset.top)
        LHSLogger.webview.notice("\(self.siteName, privacy: .public) correctScrollPosition — inset.top=\(webView.scrollView.contentInset.top, privacy: .public) offset.y=\(webView.scrollView.contentOffset.y, privacy: .public) -> target.y=\(target.y, privacy: .public)")
        webView.scrollView.setContentOffset(target, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak webView] in
            webView?.scrollView.setContentOffset(target, animated: false)
        }
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
            let _ = LHSLogger.webview.notice("\(webState.siteName, privacy: .public) GeometryReader geo.size=\(String(describing: geo.size), privacy: .public)")
            ZStack(alignment: .top) {
                if let wv = webState.webView {
                    WebViewRepresentable(webView: wv, size: geo.size, siteName: webState.siteName)
                        .ignoresSafeArea(edges: [.top, .bottom])
                        .onAppear {
                            webState.applyInsets(top: LS.contentTopInset, bottom: 0)
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
    let siteName: String

    func makeUIView(context: Context) -> WKWebView {
        // Hand sizing authority to SwiftUI now — and only now. While the view was
        // preloading outside any hierarchy it kept its explicit screen-sized
        // frame (see initialize()); from this point on, Auto Layout constraints
        // generated from .frame() own sizing, which is what the iPad
        // NavigationSplitView detail column needs in order to size the web view
        // to the narrower pane rather than full screen.
        webView.translatesAutoresizingMaskIntoConstraints = false
        LHSLogger.webview.notice("\(siteName, privacy: .public) makeUIView — frame at mount \(String(describing: webView.frame), privacy: .public)")
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard size.width > 0, size.height > 0 else { return }
        let target = CGRect(origin: .zero, size: size)
        if uiView.frame != target {
            let oldFrame = uiView.frame
            uiView.frame = target
            // A frame/bounds change on UIScrollView can renormalize contentOffset
            // against the new bounds, silently undoing applyInsets()'s negative
            // top offset. This is the one event that's structurally different on
            // first mount (webview starts at initialize()'s UIScreen.main.bounds;
            // GeometryReader's real target size can differ) vs. every later
            // re-appearance (frame already equals target, this branch never runs
            // again) — so it's re-snapped here on every occurrence this fires,
            // same guarded pattern as applyInsets, not a one-time correction.
            let top = uiView.scrollView.contentInset.top
            let needsResnap = uiView.scrollView.contentOffset.y > -top
            LHSLogger.webview.notice("\(siteName, privacy: .public) updateUIView forcing frame \(String(describing: oldFrame), privacy: .public) -> \(String(describing: target), privacy: .public), inset.top=\(top, privacy: .public) offset.y=\(uiView.scrollView.contentOffset.y, privacy: .public) resnap=\(needsResnap, privacy: .public)")
            if needsResnap {
                uiView.scrollView.setContentOffset(CGPoint(x: 0, y: -top), animated: false)
            }
        }
    }
}
