import SwiftUI
import WebKit

/// A web page shown inside the app, with no address bar and no way to copy or
/// share its links: the rules and privacy pages, blog and notification links.
struct WebPageView: View {
    let url: URL
    var title: String?

    @Environment(\.dismiss) private var dismiss
    @State private var pageTitle = ""
    @State private var progress = 0.0

    var body: some View {
        NavigationStack {
            WebViewRepresentable(url: url, title: $pageTitle, progress: $progress)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if progress < 1 {
                        ProgressView(value: progress)
                            .tint(Theme.accentText)
                    }
                }
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle(title ?? pageTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                    }
                }
        }
    }
}

/// Makes `URL` usable with `.sheet(item:)`.
struct WebLink: Identifiable, Hashable {
    let url: URL
    var title: String?
    var id: URL { url }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    @Binding var title: String
    @Binding var progress: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // No long-press menu on links and images, so their addresses stay hidden.
        let style = "* { -webkit-touch-callout: none !important; }"
        let script = WKUserScript(
            source: "var s=document.createElement('style');s.innerHTML='\(style)';document.documentElement.appendChild(s);",
            injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsLinkPreview = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.observe(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let parent: WebViewRepresentable
        private var observations: [NSKeyValueObservation] = []

        init(_ parent: WebViewRepresentable) { self.parent = parent }

        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.estimatedProgress) { [weak self] view, _ in
                    DispatchQueue.main.async { self?.parent.progress = view.estimatedProgress }
                },
                webView.observe(\.title) { [weak self] view, _ in
                    DispatchQueue.main.async { self?.parent.title = view.title ?? "" }
                },
            ]
        }

        /// Web links stay in this view; app links (tg://, intent://) are dropped.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
            if url.scheme == "kelaketfilm" {
                decisionHandler(.cancel)
                Task { @MainActor in AppRouter.shared.open(url) }
                return
            }
            decisionHandler(["http", "https", "about", "data"].contains(url.scheme ?? "") ? .allow : .cancel)
        }

        /// `target="_blank"` links open in the same view instead of a new window.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}
