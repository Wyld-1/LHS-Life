//
//  EmbeddedWebState.swift
//  LHS Life
//
//  Generic web view state + view for Lunch, PowerSchool, and Schoology.
//  Mobile user agent forces responsive mobile layout on all sites.
//

import SwiftUI
internal import WebKit

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
            self?.state?.canGoBack = webView.canGoBack
            // Inject email on Microsoft login page
            self?.state?.injectEmailIfNeeded(into: webView)
        }
    }
    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError e: Error) {
        Task { @MainActor [weak self] in
            self?.state?.isLoading = false
            self?.state?.loadError = e
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError e: Error) {
        Task { @MainActor [weak self] in
            self?.state?.isLoading = false
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

    private static let cssScript = WKUserScript(
        source: """
            var style = document.createElement('style');
            style.textContent = `\(darkModeCSS)`;
            document.head.appendChild(style);
            """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
    )

    @MainActor
    func initialize() {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        if injectDarkCSS {
            config.userContentController.addUserScript(Self.cssScript)
        }
        let wv = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        wv.customUserAgent = Self.mobileUserAgent
        wv.backgroundColor = UIColor(red: 0.074, green: 0.086, blue: 0.11, alpha: 1)
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
        wv.translatesAutoresizingMaskIntoConstraints = false
        webView = wv
        isReady  = true
        isLoading = true
        wv.load(URLRequest(url: url))
    }

    @MainActor
    func applyInsets(top: CGFloat, bottom: CGFloat) {
        guard let wv = webView else { return }
        let insets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        wv.scrollView.contentInset = insets
        wv.scrollView.verticalScrollIndicatorInsets = insets
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

    var body: some View {
        GeometryReader { geo in
            let _ = print("[WEBVIEW-SIZE] \(webState.siteName) GeometryReader geo.size=\(geo.size)")
            ZStack(alignment: .top) {
                if let wv = webState.webView {
                    WebViewRepresentable(webView: wv, size: geo.size)
                        .ignoresSafeArea(edges: [.top, .bottom])
                        .onAppear {
                            webState.applyInsets(top: LS.contentTopInset, bottom: 0)
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
    }
}

// MARK: - UIViewRepresentable

struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    let size: CGSize

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard size.width > 0, size.height > 0 else { return }
        let target = CGRect(origin: .zero, size: size)
        if uiView.frame != target {
            print("[WEBVIEW-SIZE] updateUIView — forcing frame from \(uiView.frame) to \(target)")
            uiView.frame = target
        }
    }
}
