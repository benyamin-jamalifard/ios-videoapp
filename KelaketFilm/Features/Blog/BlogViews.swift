import SwiftUI
import WebKit

struct BlogListView: View {
    @StateObject private var pager = Pager<BlogPost> { page in
        let result = try await APIClient.shared.blogPosts(page: page)
        return (result.data, result.pagination?.hasMore ?? false)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(pager.items.enumerated()), id: \.offset) { index, post in
                    NavigationLink {
                        BlogPostView(id: post.id, title: post.title ?? "")
                    } label: {
                        BlogCard(post: post)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if index == pager.items.count - 1 { Task { await pager.loadMore() } }
                    }
                }
                if pager.isLoading {
                    ProgressView().padding()
                } else if pager.isLoaded && pager.items.isEmpty {
                    Text(pager.error ?? "مطلبی منتشر نشده است.")
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 60)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("وبلاگ")
        .task { if !pager.isLoaded { await pager.reload() } }
        .refreshable { await pager.reload() }
    }
}

private struct BlogCard: View {
    let post: BlogPost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: URL(string: post.thumbnail ?? ""))
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
                if let category = post.categories.first?.name {
                    Text(category).font(.caption.bold()).foregroundStyle(Theme.accentText)
                }
                Text(post.title ?? "").font(.headline).multilineTextAlignment(.leading)
                if let excerpt = post.excerpt?.plainText, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                HStack {
                    if let author = post.author?.name { Text(author) }
                    Spacer()
                    if let date = post.displayDate { Text(date) }
                }
                .font(.caption2)
                .foregroundStyle(Theme.muted)
            }
            .padding([.horizontal, .bottom], 12)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

/// A full article, rendered as HTML.
struct BlogPostView: View {
    let id: Int
    let title: String

    @State private var post: BlogPost?
    @State private var error: String?
    @State private var openedRelated: BlogPost?

    var body: some View {
        Group {
            if let post {
                ArticleWebView(html: BlogHTML.page(for: post),
                               baseURL: APIClient.shared.siteURL,
                               onOpenPost: { id in
                                   openedRelated = post.relatedPosts.first { $0.id == id }
                               },
                               onOpenLink: { AppRouter.shared.open($0) })
                    .ignoresSafeArea(edges: .bottom)
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // navigationDestination(item:) needs iOS 17; this is the iOS 16 equivalent.
        .navigationDestination(isPresented: Binding(get: { openedRelated != nil },
                                                    set: { if !$0 { openedRelated = nil } })) {
            if let related = openedRelated {
                BlogPostView(id: related.id, title: related.title ?? "")
            }
        }
        .task { if post == nil { await load() } }
    }

    private func load() async {
        do {
            post = try await APIClient.shared.blogPost(id: id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Builds the article page: header, WordPress content, related posts.
private enum BlogHTML {
    static func page(for post: BlogPost) -> String {
        let image = post.thumbnail.map { "<img class=\"cover\" src=\"\(escape($0))\">" } ?? ""
        let meta = [post.author?.name, post.displayDate].compactMap { $0 }.map(escape).joined(separator: " · ")
        let related = post.relatedPosts.map { item in
            """
            <a class="related" href="kfblog://\(item.id)">
              <img src="\(escape(item.thumbnail ?? ""))"><span>\(escape(item.title ?? ""))</span>
            </a>
            """
        }.joined()

        return """
        <!doctype html>
        <html dir="rtl" lang="fa">
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: dark; }
          body { margin: 0; padding: 0 16px 40px; background: #0d0d0f; color: #e8e8ea;
                 font: -apple-system-body; font-family: -apple-system, sans-serif; line-height: 1.9; }
          img, video, iframe { max-width: 100%; height: auto; border-radius: 10px; }
          .cover { width: calc(100% + 32px); margin: 0 -16px; border-radius: 0; }
          h1 { font-size: 1.4em; line-height: 1.5; margin: 16px 0 4px; }
          .meta { color: #8c8c92; font-size: 0.8em; margin-bottom: 16px; }
          a { color: #f6c228; }
          blockquote { margin: 0; padding: 4px 14px; border-right: 3px solid #f6c228; color: #bbb; }
          h3.rel { margin-top: 32px; }
          .related { display: flex; gap: 12px; align-items: center; margin: 10px 0;
                     color: inherit; text-decoration: none; }
          .related img { width: 96px; height: 64px; object-fit: cover; border-radius: 8px; }
        </style>
        </head>
        <body>
        \(image)
        <h1>\(escape(post.title ?? ""))</h1>
        <div class="meta">\(meta)</div>
        \(post.content ?? "")
        \(related.isEmpty ? "" : "<h3 class=\"rel\">مطالب مرتبط</h3>" + related)
        </body>
        </html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private struct ArticleWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    let onOpenPost: (Int) -> Void
    let onOpenLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ArticleWebView

        init(parent: ArticleWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            // Related posts open in-app; every other link goes to Safari.
            if url.scheme == "kfblog", let id = Int(url.host ?? "") {
                parent.onOpenPost(id)
            } else {
                parent.onOpenLink(url)
            }
            decisionHandler(.cancel)
        }
    }
}
