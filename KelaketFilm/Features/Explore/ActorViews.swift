import SwiftUI

/// An actor's bio and filmography (`mobile/v2/actorWorks/{id}`).
struct ActorView: View {
    let actorId: Int
    let name: String
    let image: String?
    var bio: String?

    @State private var works: [Post]?
    @State private var error: String?
    @State private var showFullBio = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                RemoteImage(url: URL(string: image ?? ""))
                    .frame(width: 110, height: 110)
                    .clipShape(Circle())
                Text(name).font(.title3.bold())

                if let bio = bio?.plainText, !bio.isEmpty {
                    Text(bio)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(showFullBio ? nil : 4)
                        .onTapGesture { withAnimation { showFullBio.toggle() } }
                        .padding(.horizontal)
                }
            }
            .padding(.top)

            if let works {
                if works.isEmpty {
                    Text(L("اثری ثبت نشده است.", "No titles yet.")).foregroundStyle(Theme.muted).padding(.top, 30)
                } else {
                    Text("\(works.count) اثر")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .top])
                    PosterGrid(posts: works)
                }
            } else if let error {
                Text(error).foregroundStyle(.orange).padding(.top, 30)
            } else {
                ProgressView().padding(.top, 30)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard works == nil else { return }
            do {
                works = try await APIClient.shared.actorWorks(actorId: actorId)
            } catch is CancellationError {
                // Superseded or the screen closed: not an error to show.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Searchable, paged list of all actors.
struct ActorsArchiveView: View {
    @State private var search = ""
    @StateObject private var pager = Pager<ActorSummary> { _ in ([], false) }

    var body: some View {
        List {
            ForEach(Array(pager.items.enumerated()), id: \.offset) { index, actor in
                NavigationLink {
                    ActorView(actorId: actor.id, name: actor.name ?? "", image: actor.image)
                } label: {
                    HStack(spacing: 12) {
                        RemoteImage(url: URL(string: actor.image ?? ""))
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        Text(actor.name ?? "")
                        Spacer()
                        if let count = actor.count {
                            Text("\(count) اثر").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
                .onAppear {
                    if index == pager.items.count - 1 { Task { await pager.loadMore() } }
                }
            }
            if pager.isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if pager.isLoaded && pager.items.isEmpty {
                Text(pager.error ?? L("بازیگری پیدا نشد.", "No actors found."))
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("بازیگران", "Actors"))
        .searchable(text: $search, prompt: L("نام بازیگر", "Actor name"))
        .task(id: search) {
            let text = search.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                // Debounce typing.
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
            }
            pager.replaceFetch { page in
                let result = try await APIClient.shared.actors(search: text, page: page)
                return (result.data, result.pagination?.hasMore ?? false)
            }
            await pager.reload()
        }
    }
}
