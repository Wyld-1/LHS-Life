//
//  EmbeddedWebState.swift
//  LHS Life
//
//  Generic web view state + view for Lunch, PowerSchool, and Schoology.
//  The WKWebView fills the entire screen (including behind header + dock).
//  Content insets push the actual page content into the visible area.
//  A gradient overlay fades the top edge into the app background color.
//

import SwiftUI
import WebKit

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
        Task { @MainActor [weak self] in self?.state?.isLoading = false }
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
        wv.backgroundColor = UIColor(red: 0.074, green: 0.086, blue: 0.11, alpha: 1)
        wv.scrollView.backgroundColor = .clear
        wv.isOpaque = true
        // Don't clip to safe area — we manage insets manually
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.navigationDelegate = delegate
        webView = wv
        isReady  = true
        isLoading = true
        wv.load(URLRequest(url: url))
    }

    /// Call after geometry is known to push content below header and above dock.
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
}

// MARK: - View

struct EmbeddedWebView: View {
    @Bindable var webState: EmbeddedWebState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {

                // Web view — fills the entire screen including behind chrome
                if let wv = webState.webView {
                    WebViewRepresentable(webView: wv)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .ignoresSafeArea()
                        .onAppear {
                            // Top: status bar + header pill (~88pt) + a little breathing room
                            // Bottom: home indicator + dock height + extra padding
                            let topInset    = 140.0
                            let bottomInset = 0.0
                            webState.applyInsets(top: topInset, bottom: bottomInset)
                        }
                }

                // Loading state
                if webState.isLoading || !webState.isReady {
                    Color.lsBackground.ignoresSafeArea()
                    ProgressView()
                        .tint(Color.lsBlue)
                        .scaleEffect(1.3)
                }

                // Error state
                if let error = webState.loadError {
                    Color.lsBackground.ignoresSafeArea()
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

                // Top gradient — blends page content into app background under the header.
                LinearGradient(
                    stops: [
                        .init(color: .lsBackground, location: 0),
                        .init(color: .lsBackground, location: 0.5),
                        .init(color: .lsBackground.opacity(0), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
        }
        .background(Color.lsBackground)
        .ignoresSafeArea()
        .animation(.lsFade, value: webState.isLoading)
        .animation(.lsFade, value: webState.isReady)
    }
}

// MARK: - UIViewRepresentable

struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
