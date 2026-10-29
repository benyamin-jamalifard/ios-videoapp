import UIKit
import SwiftUI

/// A poster or backdrop, through `ImageLoader` (memory, then disk, then the
/// network), so images already seen also show offline.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
        _image = State(initialValue: url.flatMap { ImageLoader.cachedImage(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(Theme.surfaceRaised)
                    .overlay(Image(systemName: "film").font(.title3).foregroundStyle(.white.opacity(0.12)))
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = ImageLoader.cachedImage(for: url) {
                image = cached
                return
            }
            let loaded = await ImageLoader.shared.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

struct PosterCard: View {
    let post: Post
    var width: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: post.posterURL)
                .frame(width: width, height: width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .overlay(alignment: .topLeading) {
                    if let rating = post.imdbRating {
                        Label(rating, systemImage: "star.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.7), in: Capsule())
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) { PosterBadges(post: post).padding(6) }
                .overlay(alignment: .bottom) {
                    if let badge = post.badgeLabel {
                        Text(badge)
                            .font(.caption2.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(Color(hex: post.badgeColor) ?? Theme.accent)
                            .clipShape(UnevenRoundedCorners(radius: Theme.cornerRadius))
                    }
                }

            Text(post.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}

/// The small subtitle (CC) and dub (mic) marks the Android app puts on posters.
struct PosterBadges: View {
    let post: Post

    var body: some View {
        HStack(spacing: 4) {
            if post.doble { badge("mic.fill") }
            if post.def { badge("captions.bubble.fill") }
        }
    }

    private func badge(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .frame(width: 22, height: 22)
            .background(.black.opacity(0.6), in: Circle())
    }
}

/// Rounds only the bottom corners (iOS 16 has no UnevenRoundedRectangle).
private struct UnevenRoundedCorners: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect,
                          byRoundingCorners: [.bottomLeft, .bottomRight],
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

struct PostRow: View {
    let title: String
    let posts: [Post]
    /// Adds a "see all" link to the archive with this filter.
    var seeAll: ArchiveFilter? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent)
                    .frame(width: 4, height: 18)
                Text(title)
                    .font(.headline)
                Spacer()
                if let seeAll {
                    NavigationLink {
                        ArchiveView(title: title, filter: seeAll)
                    } label: {
                        HStack(spacing: 4) {
                            Text(L("مشاهده همه", "See all"))
                            Image(systemName: "chevron.forward").font(.caption2.bold())
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(posts) { post in
                        NavigationLink(value: FilmRoute(id: post.id)) {
                            PosterCard(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// A section heading with the accent bar used across the app.
struct SectionTitle: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.accent)
                .frame(width: 4, height: 18)
            Text(text).font(.headline)
        }
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(Theme.muted)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Button(L("تلاش دوباره", "Try again"), action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .foregroundStyle(.white)
    }
}

/// Navigation value for opening a film or series page.
struct FilmRoute: Hashable {
    let id: Int
}

/// Adaptive poster grid; `onReachEnd` fires when the last card appears, for paging.
struct PosterGrid: View {
    let posts: [Post]
    var onReachEnd: (() -> Void)?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 16) {
            ForEach(Array(posts.enumerated()), id: \.offset) { index, post in
                NavigationLink(value: FilmRoute(id: post.id)) {
                    PosterCard(post: post, width: 105)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if index == posts.count - 1 { onReachEnd?() }
                }
            }
        }
        .padding()
    }
}

/// Page-by-page loading shared by the archive-style screens.
@MainActor
final class Pager<Item>: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var isLoaded = false

    private var page = 0
    private var hasMore = true
    /// Returns the items of a 1-based page and whether more pages follow.
    private var fetch: (Int) async throws -> (items: [Item], hasMore: Bool)

    init(fetch: @escaping (Int) async throws -> (items: [Item], hasMore: Bool)) {
        self.fetch = fetch
    }

    /// For screens whose query changes (filters, search text); call `reload()` after.
    func replaceFetch(_ fetch: @escaping (Int) async throws -> (items: [Item], hasMore: Bool)) {
        self.fetch = fetch
    }

    func reload() async {
        page = 0
        hasMore = true
        items = []
        isLoaded = false
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await fetch(page + 1)
            page += 1
            items += result.items
            hasMore = result.hasMore && !result.items.isEmpty
            error = nil
        } catch {
            if items.isEmpty { self.error = error.localizedDescription }
        }
        isLoaded = true
    }
}
