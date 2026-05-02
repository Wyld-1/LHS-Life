//
//  LunchTabView.swift
//  LHS Life
//
//  LunchWebState is owned by AppTabContainer and passed in here.
//  This view does zero initialization work — it just renders whatever
//  state the webview is already in. Tab switching is instant.
//

import SwiftUI
import WebKit

// MARK: - Web State (owned by AppTabContainer)

@Observable
final class LunchWebState {
    var isLoading = false
    var loadError: Error? = nil
    var isReady = false

    private(set) var webView: WKWebView? = nil
    static let lunchURL = URL(string: "https://lhs.plan.tech/lunch/")!

    // CSS injected after every page load — forces dark-friendly text and background
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

    /// Called from AppTabContainer's .task — after first frame, off the layout pass.
    @MainActor
    func initialize() {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(Self.cssScript)
        let wv = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        wv.backgroundColor = UIColor(red: 0.074, green: 0.086, blue: 0.11, alpha: 1)
        wv.scrollView.backgroundColor = .clear
        wv.isOpaque = true
        webView = wv
        isReady = true
        isLoading = true
        wv.load(URLRequest(url: Self.lunchURL))
    }

    @MainActor
    func reload() {
        guard let wv = webView else { return }
        loadError = nil
        isLoading = true
        wv.load(URLRequest(url: Self.lunchURL))
    }
}

// MARK: - View

struct LunchTabView: View {
    // Passed in from AppTabContainer — this view owns nothing heavy
    let webState: LunchWebState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.lsBackground.ignoresSafeArea()

                if let wv = webState.webView {
                    LunchWebViewRepresentable(webView: wv, webState: webState)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .ignoresSafeArea()
                }

                if webState.isLoading || !webState.isReady {
                    Color.lsBackground.ignoresSafeArea()
                    ProgressView()
                        .tint(Color.lsBlue)
                        .scaleEffect(1.3)
                }

                if let error = webState.loadError {
                    Color.lsBackground.ignoresSafeArea()
                    VStack(spacing: LS.md) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.lsSecondary)
                        Text("Couldn't load lunch orders")
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
        .ignoresSafeArea()
        .animation(.lsFade, value: webState.isLoading)
        .animation(.lsFade, value: webState.isReady)
    }
}

// MARK: - UIViewRepresentable

private struct LunchWebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    let webState: LunchWebState

    func makeCoordinator() -> Coordinator { Coordinator(webState: webState) }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let webState: LunchWebState
        init(webState: LunchWebState) { self.webState = webState }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            Task { @MainActor in webState.isLoading = true; webState.loadError = nil }
        }
        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            Task { @MainActor in webState.isLoading = false }
        }
        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError e: Error) {
            Task { @MainActor in webState.isLoading = false; webState.loadError = e }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError e: Error) {
            Task { @MainActor in webState.isLoading = false; webState.loadError = e }
        }
    }
}
