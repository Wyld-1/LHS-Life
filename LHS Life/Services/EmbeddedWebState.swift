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
import UniformTypeIdentifiers
import QuickLook

// MARK: - UI Delegate (print, new-tab links)

/// Catches window.open() / target="_blank" and window.print().
///
/// WKWebView implements neither browser API by default — that's the whole
/// reason Schoology's Print and "open in new tab" links did nothing in the
/// wrapped app while working perfectly in Safari. Safari supplies both;
/// WKWebView supplies neither, and expects the host app to.
final class EmbeddedWebUIDelegate: NSObject, WKUIDelegate {
    weak var state: EmbeddedWebState?

    /// A same-tab embedded browser has nowhere to put a "new window" — so
    /// target="_blank" links are loaded in the SAME web view instead of
    /// silently doing nothing, which is what happens if this delegate method
    /// is left unimplemented.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    /// iOS 16.4+ hook for window.print(). Delegates to EmbeddedWebState so
    /// the actual UIPrintInteractionController presentation logic lives in
    /// one place rather than duplicated across every page that calls print().
    @available(iOS 16.4, *)
    func webView(_ webView: WKWebView, printFrame frame: WKFrameInfo?) {
        Task { @MainActor [weak state] in
            state?.presentPrintDialog(for: webView)
        }
    }
}

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

    // MARK: Downloads
    //
    // Content-Disposition is the signal, NOT canShowMIMEType.
    //
    // The first version of this checked canShowMIMEType and only downloaded
    // what WebKit couldn't render. That was wrong: WebKit CAN render
    // application/pdf, so a PDF returned .allow and navigated inline — which
    // is exactly the "opens a one-page document inside Schoology" symptom.
    // Safari downloads the same response because the server sends
    // Content-Disposition: attachment, and Safari honours that header. WebKit
    // ignores it unless the host app acts on it.
    //
    // Documents are ALSO routed to download even when inline-renderable, so
    // they land in QuickLook — which paginates properly, and whose toolbar
    // carries Print, Save to Files and AirDrop. Inline WebKit PDF rendering
    // inside a wrapped view has none of that.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let response = navigationResponse.response
        let mime = response.mimeType?.lowercased() ?? ""
        var disposition = ""
        if let http = response as? HTTPURLResponse,
           let value = http.value(forHTTPHeaderField: "Content-Disposition") {
            disposition = value.lowercased()
        }

        LHSLogger.liveActivity.notice(
            """
            [Web] response \(response.url?.lastPathComponent ?? "?", privacy: .public) \
            mime: \(mime, privacy: .public) \
            disposition: \(disposition.isEmpty ? "none" : disposition, privacy: .public) \
            canShow: \(navigationResponse.canShowMIMEType)
            """
        )

        let isAttachment = disposition.contains("attachment")
        let isDocument =
            mime == "application/pdf" ||
            mime.contains("officedocument") ||
            mime.contains("msword") ||
            mime.contains("ms-excel") ||
            mime.contains("ms-powerpoint") ||
            mime == "application/zip" ||
            mime == "application/octet-stream"

        if isAttachment || isDocument || !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        Task { @MainActor [weak self] in
            download.delegate = self?.state
        }
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        Task { @MainActor [weak self] in
            download.delegate = self?.state
        }
    }
}

// MARK: - Web State

@Observable
final class EmbeddedWebState: NSObject {

    var isLoading = false
    var loadError: Error? = nil
    var isReady   = false
    var canGoBack = false

    /// Non-nil while a download is in flight, so the view can show a spinner
    /// instead of leaving the person wondering whether the tap registered.
    var isDownloading = false

    /// A completed download waiting to be shown. QuickLook's own share sheet
    /// button covers "Save to Files" / AirDrop / Print, so nothing custom is
    /// needed once the file has landed — this hands off to a system-provided
    /// experience rather than building another one.
    var downloadedFileURL: URL? = nil

    private(set) var webView: WKWebView? = nil
    private let navDelegate = EmbeddedWebDelegate()
    private let uiDelegate  = EmbeddedWebUIDelegate()

    let url: URL
    let siteName: String
    let injectDarkCSS: Bool

    init(url: URL, siteName: String, injectDarkCSS: Bool = false) {
        self.url           = url
        self.siteName      = siteName
        self.injectDarkCSS = injectDarkCSS
        super.init()
        navDelegate.state  = self
        uiDelegate.state   = self
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

    /// Overrides window.print() in every frame and forwards the call to native.
    ///
    /// The WKUIDelegate printFrame hook is the documented route, but it never
    /// fired against Schoology — so rather than keep guessing which code path
    /// their button uses, this intercepts the API itself. Works regardless of
    /// whether print() is called from the top document, a nested iframe, an
    /// onclick handler, or a window opened by their JS.
    ///
    /// forMainFrameOnly: false is what makes the iframe case work; Schoology
    /// renders document previews in nested frames.
    private static let printOverrideScript = """
        (function() {
            if (window.__lhsPrintHooked) return;
            window.__lhsPrintHooked = true;
            window.print = function() {
                try {
                    window.webkit.messageHandlers.lhsPrint.postMessage({
                        url: document.location.href
                    });
                } catch (e) {}
            };
        })();
        """

    private static func userScript(isDark: Bool) -> WKUserScript {
        WKUserScript(
            source: isDark ? injectionScript : removalScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }

    /// Injected into every frame at document start — before page scripts run,
    /// so a page that caches a reference to window.print gets ours.
    private static func printScript() -> WKUserScript {
        WKUserScript(
            source: printOverrideScript,
            injectionTime: .atDocumentStart,
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
        config.userContentController.addUserScript(Self.printScript())
        config.userContentController.add(self, name: "lhsPrint")
        let wv = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        wv.customUserAgent = Self.mobileUserAgent
        // Matches the app canvas in whichever mode is actually active —
        // previously hardcoded dark for all three sites (Lunch, PowerSchool,
        // Schoology), which would flash dark during load even in light mode.
        wv.backgroundColor = isDark ? Self.darkWebBackground : Self.lightWebBackground
        wv.scrollView.backgroundColor = .clear
        wv.isOpaque = true
        wv.scrollView.contentInsetAdjustmentBehavior = .always
        wv.navigationDelegate = navDelegate
        wv.uiDelegate = uiDelegate
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
        // removeAllUserScripts() is indiscriminate — it drops the print hook
        // too, so it has to be re-added or printing silently stops working
        // the first time the appearance changes mid-session.
        wv.configuration.userContentController.addUserScript(Self.printScript())
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

    // MARK: - Print

    /// Renders the currently-loaded page via UIPrintInteractionController.
    ///
    /// viewPrintFormatter() is what actually paginates and rasterizes the
    /// page content — it is the ONE piece of this whole feature that WebKit
    /// does provide, which is why print doesn't need WKDownloadDelegate or
    /// any file handling at all. It just needed something to call it.
    @MainActor
    func presentPrintDialog(for webView: WKWebView) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = siteName
        controller.printInfo = info
        controller.printFormatter = webView.viewPrintFormatter()
        controller.present(animated: true, completionHandler: nil)
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

// MARK: - Script Message Handler (print)

extension EmbeddedWebState: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "lhsPrint" else { return }
        LHSLogger.liveActivity.notice("[Web] window.print() intercepted")
        Task { @MainActor [weak self] in
            guard let self, let wv = self.webView else { return }
            self.presentPrintDialog(for: wv)
        }
    }
}

// MARK: - Download Delegate

extension EmbeddedWebState: WKDownloadDelegate {

    /// Picks the destination and lets the download proceed.
    ///
    /// Written to the temp directory rather than Documents — this is a
    /// hand-off point on the way to QuickLook, not a permanent library the
    /// app is expected to manage; QuickLook's own share sheet is where the
    /// person decides whether to keep it (Save to Files) or send it
    /// elsewhere. A stale temp file surviving a relaunch is an acceptable
    /// cost for not having to build file-lifecycle management for a
    /// pass-through view.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        Task { @MainActor in
            self.isDownloading = true
        }
        let dir = FileManager.default.temporaryDirectory
        // Downloading the same document twice in one session must not
        // collide on the first attempt's leftover file — WKDownload will not
        // overwrite an existing file and instead fails the whole download.
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(suggestedFilename))
        completionHandler(dir.appendingPathComponent(suggestedFilename))
    }

    func downloadDidFinish(_ download: WKDownload) {
        Task { @MainActor in
            self.isDownloading = false
            if let url = download.progress.fileURL {
                self.downloadedFileURL = url
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error,
                  resumeData: Data?) {
        Task { @MainActor in
            self.isDownloading = false
            print("[Download] Failed: \(error)")
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

                // No loading cover, first load included.
                //
                // Progress is reported by the toolbar instead: the back button
                // becomes a spinner while a page is in flight, on iPhone and
                // iPad alike (PhoneToolbar, iPadRootView.isWebTabLoading).
                // That was already true for every navigation AFTER the first
                // one; the first load kept an opaque full-screen cover, which
                // on iPad is a lot of screen to black out while the chrome
                // sits there with a perfectly good spinner in it.
                //
                // What's underneath during a first load is the empty web view
                // on the app's own background, which is what a browser shows
                // too. The error state below still takes the screen, because
                // an error is a dead end rather than a wait.

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
        .overlay(alignment: .top) {
            if webState.isDownloading {
                // Sits below the toolbar rather than centered — a download
                // is a background event the person doesn't need to stop and
                // watch, unlike the full-screen spinner on first load.
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Downloading…")
                        .font(.lsCaption)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.7), in: Capsule())
                .padding(.top, LS.contentTopInset + LS.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.lsFade, value: webState.isDownloading)
        // QuickLook rather than a custom viewer: it already renders every
        // format Schoology serves (PDF, Office docs, images), and its own
        // toolbar supplies Print, Save to Files, and AirDrop — the exact set
        // of actions Print/Download were supposed to unlock. Building a
        // second version of that would be redundant with what iOS ships.
        .quickLookPreview(Binding(
            get: { webState.downloadedFileURL },
            set: { webState.downloadedFileURL = $0 }
        ))
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
