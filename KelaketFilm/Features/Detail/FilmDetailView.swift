import SwiftUI
import UIKit

struct FilmDetailView: View {
    let id: Int

    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @State private var detail: FilmDetail?
    @State private var error: String?
    @State private var playback: PlaybackItem?
    @State private var showLogin = false
    @State private var showAddToList = false
    @State private var selectedSeason = 0
    @State private var notice: String?

    var body: some View {
        Group {
            if let detail {
                content(detail)
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(detail?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let detail {
                    if detail.isSeries {
                        Button { Task { await toggleNotification() } } label: {
                            Image(systemName: detail.notified ? "bell.fill" : "bell")
                        }
                    }
                    if appState.config.kelaketappShowMylist {
                        Button { Task { await toggleWatchlist() } } label: {
                            Image(systemName: detail.watchlisted ? "bookmark.fill" : "bookmark")
                        }
                    }
                    Button {
                        if appState.isSignedIn { showAddToList = true } else { showLogin = true }
                    } label: {
                        Image(systemName: "text.badge.plus")
                    }
                }
            }
        }
        // Reload after login: links and watch progress depend on the user.
        .task(id: appState.token) { await load() }
        .fullScreenCover(item: $playback) { item in
            PlayerView(item: item)
                .environmentObject(appState)
                .onDisappear { Task { await load() } }
        }
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(appState)
        }
        .sheet(isPresented: $showAddToList) {
            AddToListSheet(postId: id).environmentObject(appState)
        }
        .alert(notice ?? "", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("باشه", role: .cancel) {}
        }
    }

    private func load() async {
        do {
            detail = try await appState.api.film(id: id)
            error = nil
        } catch {
            if detail == nil { self.error = error.localizedDescription }
        }
    }

    // MARK: Layout

    private func content(_ detail: FilmDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(detail)
                primaryActions(detail)

                if !detail.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(detail.genres.enumerated()), id: \.offset) { _, genre in
                                NavigationLink {
                                    ArchiveView(title: genre.name ?? "", filter: ArchiveFilter(genre: genre.id))
                                } label: {
                                    Text(genre.name ?? "")
                                        .font(.caption)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Theme.surface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if let story = detail.story ?? detail.about {
                    Text(story.plainText)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(5)
                        .padding(.horizontal)
                }

                voteRow(detail)

                if detail.isSeries {
                    seasonsSection(detail)
                } else if !detail.filmDl.isEmpty {
                    filmLinksSection(detail)
                }

                commentsPreview(detail)

                if !detail.fullActors.isEmpty {
                    actorsRow(detail.fullActors)
                }
                if let collection = detail.collection, !collection.data.isEmpty {
                    PostRow(title: collection.name ?? collection.title ?? "کالکشن", posts: collection.data)
                }
                if !detail.related.isEmpty {
                    PostRow(title: "پیشنهادهای مشابه", posts: detail.related)
                }
            }
            .padding(.bottom, 32)
        }
    }

    private func header(_ detail: FilmDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: detail.backdropURL)
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(LinearGradient(colors: [.clear, Theme.background],
                                        startPoint: .center, endPoint: .bottom))

            HStack(alignment: .bottom, spacing: 14) {
                RemoteImage(url: detail.posterURL)
                    .frame(width: 100, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .shadow(radius: 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.displayName)
                        .font(.title3.bold())
                    if let en = detail.enTitle, en != detail.displayName {
                        Text(en).font(.caption).foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 10) {
                        if let imdb = detail.imdbRating {
                            Label(imdb, systemImage: "star.fill").foregroundStyle(.yellow)
                        }
                        if let year = detail.released {
                            Text(year)
                        }
                        if let runtime = detail.runtime {
                            Text(runtime)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal)
            .offset(y: 50)
        }
        .padding(.bottom, 50)
    }

    @ViewBuilder
    private func primaryActions(_ detail: FilmDetail) -> some View {
        VStack(spacing: 10) {
            if let progress = detail.watchProgress, let resume = resumeLink(detail, progress) {
                Button {
                    play(resume, detail: detail, season: progress.seasonNo ?? 0,
                         episode: progress.episodeNo ?? 0, row: progress.movieRowNo ?? 0,
                         startAt: Double(progress.positionSeconds ?? 0))
                } label: {
                    Label("ادامه تماشا" + (progress.episodeLabel.map { " · \($0)" } ?? ""),
                          systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if !detail.isSeries, let first = filmPlayLinks(detail, row: 0).first {
                Button {
                    play(first.url, detail: detail)
                } label: {
                    Label("پخش آنلاین", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if let trailer = detail.trailer, let url = URL(string: trailer) {
                Button {
                    openURL(url)
                } label: {
                    Label("تریلر", systemImage: "film")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    // MARK: Film links

    private func filmLinksSection(_ detail: FilmDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("پخش و دانلود").font(.headline)

            ForEach(Array(detail.filmDl.enumerated()), id: \.offset) { row, group in
                VStack(alignment: .leading, spacing: 10) {
                    if let title = group.versionLabel ?? group.rowInfo {
                        Text(title.plainText)
                            .font(.subheadline.bold())
                            .foregroundStyle(group.versionType == "dub" ? .blue : Theme.accent)
                    }

                    let playLinks = filmPlayLinks(detail, row: row)
                    if !playLinks.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(playLinks, id: \.url) { link in
                                    Button {
                                        play(link.url, detail: detail, row: row)
                                    } label: {
                                        Label(link.label, systemImage: "play.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }

                    ForEach(Array(group.data.enumerated()), id: \.offset) { _, link in
                        downloadRow(link, paid: detail.isPaid)
                    }
                }
                .padding()
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
        }
        .padding(.horizontal)
    }

    /// Online links for a film version row, falling back to the post-level fields.
    private func filmPlayLinks(_ detail: FilmDetail, row: Int) -> [(label: String, url: String)] {
        if detail.filmDl.indices.contains(row), let online = detail.filmDl[row].playonline.first {
            let byQuality = online.quality?.available ?? []
            if !byQuality.isEmpty { return byQuality }
            if let link = online.link { return [(label: "پخش", url: link)] }
            if online.hasLink { return [(label: "پخش", url: "")] }
        }
        if row == 0 {
            let byQuality = detail.onlineQuality?.available ?? []
            if !byQuality.isEmpty { return byQuality }
            if let single = detail.onlineSingle { return [(label: "پخش", url: single)] }
        }
        return []
    }

    // MARK: Series

    @ViewBuilder
    private func seasonsSection(_ detail: FilmDetail) -> some View {
        let seasons = detail.serialDl
        let index = min(selectedSeason, seasons.count - 1)
        let season = seasons[index]
        let seasonNumber = season.number(fallback: index)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("قسمت‌ها").font(.headline)
                Spacer()
                if seasons.count > 1 {
                    Picker("فصل", selection: $selectedSeason) {
                        ForEach(seasons.indices, id: \.self) { i in
                            Text(seasons[i].seasonName ?? "فصل \(i + 1)").tag(i)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            ForEach(Array(season.episode.enumerated()), id: \.offset) { offset, episode in
                let episodeNumber = episode.episodeNumber ?? offset + 1
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(episode.title ?? "قسمت \(episodeNumber)")
                                .font(.subheadline.bold())
                            if let label = episode.versionLabel {
                                Text(label)
                                    .font(.caption2)
                                    .foregroundStyle(episode.versionType == "dub" ? .blue : Theme.accent)
                            }
                        }
                        Spacer()
                        if let link = episodePlayLink(episode) {
                            Button {
                                play(link, detail: detail, season: seasonNumber, episode: episodeNumber)
                            } label: {
                                Image(systemName: "play.circle.fill").font(.title2)
                            }
                        }
                    }

                    ForEach(Array(episode.link.enumerated()), id: \.offset) { _, link in
                        downloadRow(link, paid: detail.isPaid)
                    }
                }
                .padding()
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
        }
        .padding(.horizontal)
    }

    private func episodePlayLink(_ episode: Episode) -> String? {
        if let link = episode.onlineLink { return link }
        if let best = episode.quality?.available.first { return best.url }
        // Hidden from guests: show the button so tapping it asks them to log in.
        return episode.hasOnlineLink ? "" : nil
    }

    /// Finds the link to resume from the server-side watch progress.
    private func resumeLink(_ detail: FilmDetail, _ progress: WatchProgressItem) -> String? {
        if progress.contentType == "series" {
            for (index, season) in detail.serialDl.enumerated()
            where season.number(fallback: index) == progress.seasonNo {
                for (offset, episode) in season.episode.enumerated()
                where (episode.episodeNumber ?? offset + 1) == progress.episodeNo {
                    if let link = episodePlayLink(episode) { return link }
                }
            }
            return nil
        }
        return filmPlayLinks(detail, row: progress.movieRowNo ?? 0).first?.url
    }

    // MARK: Rows

    private func downloadRow(_ link: DownloadLink, paid: Bool) -> some View {
        Menu {
            switch appState.access(to: "download", paid: paid) {
            case .needsLogin:
                Button("برای دانلود وارد شوید") { showLogin = true }
            case .needsSubscription:
                Button("دانلود نیاز به اشتراک ویژه دارد") {
                    notice = "دانلود این محتوا نیاز به اشتراک ویژه دارد."
                }
            case .allowed:
                if let url = link.link.flatMap(URL.init(string:)) {
                    if Playback.isNativelyPlayable(url) {
                        Button { play(url.absoluteString, detail: detail) } label: {
                            Label("پخش", systemImage: "play")
                        }
                    }
                    Button { openURL(url) } label: {
                        Label("دانلود با مرورگر", systemImage: "safari")
                    }
                    Button { UIPasteboard.general.string = url.absoluteString } label: {
                        Label("کپی لینک", systemImage: "doc.on.doc")
                    }
                } else {
                    Button("برای دانلود وارد شوید") { showLogin = true }
                }
            }
        } label: {
            HStack {
                Image(systemName: "arrow.down.circle")
                Text(link.quality ?? "دانلود")
                if let info = link.dlRowInfo ?? link.versionLabel {
                    Text(info.plainText).foregroundStyle(Theme.muted)
                }
                Spacer()
                if let size = link.size {
                    Text(size).foregroundStyle(Theme.muted)
                }
            }
            .font(.footnote)
            .padding(.vertical, 6)
        }
    }

    private func actorsRow(_ actors: [Actor]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("بازیگران").font(.headline).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(actors.enumerated()), id: \.offset) { _, actor in
                        NavigationLink {
                            ActorView(actorId: actor.id ?? 0, name: actor.name ?? "",
                                      image: actor.image, bio: actor.bio)
                        } label: {
                            VStack(spacing: 6) {
                                RemoteImage(url: URL(string: actor.image ?? ""))
                                    .frame(width: 70, height: 70)
                                    .clipShape(Circle())
                                Text(actor.name ?? "")
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 80)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(actor.id == nil)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func voteRow(_ detail: FilmDetail) -> some View {
        HStack {
            if let percent = detail.userVote {
                Label("رضایت کاربران: \(percent)", systemImage: "heart.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { Task { await vote("like") } } label: {
                Image(systemName: "hand.thumbsup")
            }
            Button { Task { await vote("dislike") } } label: {
                Image(systemName: "hand.thumbsdown")
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
    }

    private func commentsPreview(_ detail: FilmDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("نظرات").font(.headline)
                Spacer()
                NavigationLink {
                    CommentsView(postId: detail.id)
                } label: {
                    Text(detail.comments.isEmpty ? "ثبت نظر" : "همه نظرات (\(detail.totalComments ?? detail.comments.count))")
                        .font(.footnote)
                }
            }
            if detail.comments.isEmpty {
                Text("هنوز نظری ثبت نشده است.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            ForEach(detail.comments.prefix(3)) { comment in
                CommentRow(comment: comment)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
        }
        .padding(.horizontal)
    }

    // MARK: Actions

    private func toggleWatchlist() async {
        guard appState.isSignedIn else {
            showLogin = true
            return
        }
        do {
            let response = try await appState.api.toggleWatchlist(postId: id)
            if response.error {
                notice = response.text
            } else {
                detail?.watchlisted.toggle()
            }
        } catch {
            notice = error.localizedDescription
        }
    }

    private func toggleNotification() async {
        guard appState.isSignedIn else {
            showLogin = true
            return
        }
        do {
            let response = try await appState.api.togglePostNotification(postId: id)
            detail?.notified = response.isAdded
            notice = response.text
        } catch {
            notice = error.localizedDescription
        }
    }

    private func vote(_ action: String) async {
        guard appState.isSignedIn, let userId = appState.userId else {
            showLogin = true
            return
        }
        do {
            let response = try await appState.api.vote(postId: id, userId: userId, action: action)
            notice = response.text ?? (response.success ? "رای شما ثبت شد." : "رای ثبت نشد.")
            if response.success { await load() }
        } catch {
            notice = error.localizedDescription
        }
    }

    private func play(_ link: String, detail: FilmDetail?, season: Int = 0, episode: Int = 0,
                      row: Int = 0, startAt: Double = 0) {
        guard let detail else { return }
        switch appState.access(to: "playonline", paid: detail.isPaid) {
        case .needsLogin:
            showLogin = true
            return
        case .needsSubscription:
            notice = "برای تماشای این محتوا نیاز به اشتراک ویژه دارید."
            return
        case .allowed:
            break
        }

        guard !link.isEmpty, let url = URL(string: link) else {
            // An empty link means the server hid it: the session is no longer valid.
            showLogin = !appState.isSignedIn
            if appState.isSignedIn { notice = "لینک پخش در دسترس نیست." }
            return
        }

        if Playback.isNativelyPlayable(url) {
            playback = PlaybackItem(url: url,
                                    title: detail.displayName,
                                    postId: detail.id,
                                    contentType: detail.isSeries ? "series" : "film",
                                    seasonNo: season,
                                    episodeNo: episode,
                                    movieRowNo: row,
                                    startAt: startAt)
        } else if let external = Playback.externalPlayerURL(for: url) {
            openURL(external)
        } else {
            notice = "این فرمت ویدیو در پخش‌کننده آیفون پشتیبانی نمی‌شود. برای پخش، اپ VLC را نصب کنید."
        }
    }
}
