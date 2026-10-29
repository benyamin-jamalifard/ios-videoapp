import SwiftUI

struct FilmDetailView: View {
    let id: Int

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var network = NetworkStatus.shared
    @State private var detail: FilmDetail?
    @State private var error: String?
    @State private var playback: PlaybackItem?
    @State private var webLink: WebLink?
    @State private var showLogin = false
    @State private var showAddToList = false
    @State private var showReport = false
    @State private var selectedSeason = 0
    @State private var notice: String?

    var body: some View {
        Group {
            if let detail {
                content(detail)
                    .accessibilityIdentifier("film-detail")
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
                if let detail, !appState.isInternational {
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
        .task(id: "\(appState.token ?? "")|\(network.refreshToken)") { await load() }
        .fullScreenCover(item: $playback) { item in
            PlayerView(item: item)
                .environmentObject(appState)
                .onDisappear { Task { await load() } }
        }
        .sheet(item: $webLink) { link in
            WebPageView(url: link.url, title: link.title)
        }
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(appState)
        }
        .sheet(isPresented: $showAddToList) {
            AddToListSheet(postId: id).environmentObject(appState)
        }
        .sheet(isPresented: $showReport) {
            ReportProblemSheet(postId: id, title: detail?.displayName ?? "").environmentObject(appState)
        }
        .alert(notice ?? "", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button(L("باشه", "OK"), role: .cancel) {}
        }
    }

    private func load() async {
        do {
            let loaded = try await appState.api.film(id: id)
            if detail == nil { AppAnalytics.viewedTitle(id: loaded.id, name: loaded.displayName) }
            detail = loaded
            error = nil
        } catch is CancellationError {
            // Superseded or the screen closed: not an error to show.
        } catch {
            if detail == nil { self.error = error.localizedDescription }
        }
    }

    // MARK: Layout

    private func content(_ detail: FilmDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(detail)

                // Abroad the page is information only: no buttons, no notice.
                if !appState.isInternational {
                    primaryActions(detail)
                }

                if !detail.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(detail.genres.filter { !$0.displayName.isEmpty }.enumerated()), id: \.offset) { _, genre in
                                NavigationLink {
                                    ArchiveView(title: genre.displayName, filter: ArchiveFilter(genre: genre.id))
                                } label: {
                                    Text(genre.displayName)
                                        .font(.footnote.weight(.medium))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Theme.surfaceRaised, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // The stories are written in Persian; the English page leaves them out.
                if let story = detail.story ?? detail.about,
                   !appState.isInternational || !Localizer.containsPersian(story) {
                    ExpandableText(text: story.plainText)
                        .padding(.horizontal)
                }

                specsSection(detail)

                if !appState.isInternational {
                    voteRow(detail)

                    if detail.isSeries {
                        seasonsSection(detail)
                    } else if !detail.filmDl.isEmpty {
                        filmLinksSection(detail)
                    }

                    commentsPreview(detail)
                }

                if !detail.fullActors.isEmpty {
                    actorsRow(detail.fullActors)
                }
                if let collection = detail.collection, !collection.data.isEmpty {
                    PostRow(title: Localizer.title(collection.name ?? collection.title ?? L("کالکشن", "Collection")),
                            posts: collection.data)
                }
                if !detail.related.isEmpty {
                    PostRow(title: L("پیشنهادهای مشابه", "More like this"), posts: detail.related)
                }
            }
            .padding(.bottom, 32)
        }
    }

    private func header(_ detail: FilmDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: detail.backdropURL)
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.1), Theme.background.opacity(0.7), Theme.background],
                                        startPoint: .top, endPoint: .bottom))

            HStack(alignment: .bottom, spacing: 14) {
                RemoteImage(url: detail.posterURL)
                    .frame(width: 108, height: 162)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(.white.opacity(0.12)))
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.displayName)
                        .font(.title3.bold())
                        .lineLimit(3)
                    // Abroad, only English: the Persian name is left out.
                    if !appState.isInternational, let other = detail.enTitle, other != detail.displayName {
                        Text(other).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    HStack(spacing: 8) {
                        if let imdb = detail.imdbRating {
                            metaChip(Label(imdb, systemImage: "star.fill").foregroundStyle(.yellow))
                        }
                        if let year = detail.released {
                            metaChip(Text(year))
                        }
                        if let runtime = detail.runtime {
                            metaChip(Text(runtime))
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal)
            .offset(y: 56)
        }
        .padding(.bottom, 56)
    }

    private func metaChip<Content: View>(_ content: Content) -> some View {
        content
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Ratings, crew and production details, in both modes.
    @ViewBuilder
    private func specsSection(_ detail: FilmDetail) -> some View {
        let rows = specRows(detail)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: L("مشخصات", "Details"))
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Label(row.label, systemImage: row.icon)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 128, alignment: .leading)
                            Text(row.value)
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.disabled)
                        }
                        .padding(.vertical, 10)
                        if index < rows.count - 1 {
                            Divider().overlay(Theme.surfaceRaised)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .padding(.horizontal)
        }
    }

    private func specRows(_ detail: FilmDetail) -> [(label: String, icon: String, value: String)] {
        func clean(_ value: String?) -> String? {
            guard let value = value?.plainText, !value.isEmpty, value != "N/A", value != "0" else { return nil }
            // "English, English, English" → "English".
            var seen: [String] = []
            for part in value.components(separatedBy: CharacterSet(charactersIn: ",،")) {
                let item = part.trimmingCharacters(in: .whitespaces)
                if !item.isEmpty, !seen.contains(item) { seen.append(item) }
            }
            return seen.joined(separator: L("، ", ", "))
        }
        var rows: [(label: String, icon: String, value: String)] = []
        func add(_ label: String, _ icon: String, _ value: String?) {
            if let value = clean(value) { rows.append((label, icon, value)) }
        }
        if let imdb = clean(detail.imdbRating) {
            let votes = clean(detail.imdbVotes).flatMap { Int($0.filter(\.isNumber)) }
            add("IMDb", "star.fill", imdb + (votes.map { L(" از ۱۰ · \($0.formatted()) رأی", " / 10 · \($0.formatted()) votes") } ?? ""))
        }
        add("Rotten Tomatoes", "leaf.fill", detail.rotten)
        add("Metacritic", "chart.bar.fill", detail.metacritic)
        add(L("کارگردان", "Director"), "megaphone.fill", detail.director)
        add(L("نویسنده", "Writer"), "pencil", detail.writer)
        if detail.fullActors.isEmpty { add(L("بازیگران", "Cast"), "person.2.fill", detail.actors) }
        add(L("ژانر", "Genre"), "theatermasks.fill", detail.genres.map(\.displayName).joined(separator: ", "))
        add(L("کشور", "Country"), "globe", detail.countries.map(\.displayName).joined(separator: ", "))
        add(L("زبان", "Language"), "character.bubble.fill", detail.language)
        add(L("سال انتشار", "Released"), "calendar", detail.releasedDate ?? detail.released)
        add(L("مدت زمان", "Runtime"), "clock.fill", detail.runtime)
        add(L("رده سنی", "Rated"), "person.badge.shield.checkmark.fill", detail.rate)
        if detail.isSeries {
            let episodes = detail.serialDl.reduce(0) { $0 + $1.episode.count }
            add(L("فصل‌ها", "Seasons"), "square.stack.fill", String(detail.serialDl.count))
            if episodes > 0 { add(L("قسمت‌ها", "Episodes"), "list.number", String(episodes)) }
            add(L("وضعیت", "Status"), "dot.radiowaves.left.and.right",
                appState.isInternational ? detail.airStatus.map(Localizer.title) : detail.airStatus)
        }
        add(L("جوایز", "Awards"), "trophy.fill", detail.awards)
        // Persian-only values (such as a Persian director name) are skipped abroad.
        if appState.isInternational {
            rows.removeAll { Localizer.containsPersian($0.value) }
        }
        return rows
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
            } else if detail.isSeries, let first = firstEpisode(detail) {
                Button {
                    play(first.link, detail: detail, season: first.season, episode: first.episode)
                } label: {
                    Label("پخش قسمت اول", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if let trailer = detail.trailer, let url = URL(string: trailer) {
                Button {
                    playTrailer(url, detail: detail)
                } label: {
                    Label(L("تریلر", "Trailer"), systemImage: "film")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    // MARK: Film links

    private func filmLinksSection(_ detail: FilmDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle(text: "پخش و دانلود")
                Spacer()
                ReportProblemButton { showReport = true }
            }

            ForEach(Array(detail.filmDl.enumerated()), id: \.offset) { row, group in
                VStack(alignment: .leading, spacing: 12) {
                    if let title = group.versionLabel ?? group.rowInfo {
                        Text(title.plainText)
                            .font(.subheadline.bold())
                            .foregroundStyle(group.versionType == "dub" ? Theme.dubbed : Theme.accentText)
                    }

                    let playLinks = filmPlayLinks(detail, row: row)
                    if !playLinks.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(playLinks, id: \.url) { link in
                                    Button {
                                        play(link.url, detail: detail, row: row)
                                    } label: {
                                        Label(link.label, systemImage: "play.fill")
                                            .font(.footnote.bold())
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(Theme.accent, in: Capsule())
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    ForEach(Array(group.data.enumerated()), id: \.offset) { _, link in
                        downloadRow(link, detail: detail,
                                    target: .init(row: row, season: 0, episode: 0, label: nil))
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
                SectionTitle(text: "قسمت‌ها")
                Spacer()
                ReportProblemButton { showReport = true }
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
                        VStack(alignment: .leading, spacing: 3) {
                            Text(episode.title ?? "قسمت \(episodeNumber)")
                                .font(.subheadline.bold())
                            if let label = episode.versionLabel {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(episode.versionType == "dub" ? Theme.dubbed : Theme.accentText)
                            }
                        }
                        Spacer()
                        if let link = episodePlayLink(episode) {
                            Button {
                                play(link, detail: detail, season: seasonNumber, episode: episodeNumber)
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.body.bold())
                                    .frame(width: 40, height: 40)
                                    .background(Theme.accent, in: Circle())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(Array(episode.link.enumerated()), id: \.offset) { _, link in
                        downloadRow(link, detail: detail,
                                    target: .init(row: 0, season: seasonNumber, episode: episodeNumber,
                                                  label: "فصل \(seasonNumber) · قسمت \(episodeNumber)"))
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

    private func firstEpisode(_ detail: FilmDetail) -> (link: String, season: Int, episode: Int)? {
        for (index, season) in detail.serialDl.enumerated() {
            for (offset, episode) in season.episode.enumerated() {
                if let link = episodePlayLink(episode) {
                    return (link, season.number(fallback: index), episode.episodeNumber ?? offset + 1)
                }
            }
        }
        return nil
    }

    /// The soft subtitle that belongs to a video link: from its online row or
    /// episode, or a .vtt/.srt row in the same download group.
    private func subtitleURL(for link: String, in detail: FilmDetail) -> URL? {
        func isSubtitle(_ value: String) -> Bool {
            let ext = URL(string: value)?.pathExtension.lowercased()
            return ext == "vtt" || ext == "srt"
        }
        func matches(_ quality: QualityLinks?) -> Bool {
            quality?.available.contains { option in option.url == link } ?? false
        }
        var found: String?
        for group in detail.filmDl where found == nil {
            let online = group.playonline.first { row in row.link == link || matches(row.quality) }
            if let subtitle = online?.subtitle {
                found = subtitle
            } else if online != nil || group.data.contains(where: { row in row.link == link }) {
                found = group.playonline.compactMap(\.subtitle).first
                    ?? group.data.compactMap(\.link).first(where: isSubtitle)
            }
        }
        for season in detail.serialDl where found == nil {
            let episode = season.episode.first { episode in
                episode.onlineLink == link
                    || matches(episode.quality)
                    || episode.link.contains { row in row.link == link }
            }
            found = episode?.subtitle
        }
        return found.flatMap(URL.init(string:))
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

    private func downloadRow(_ link: DownloadLink, detail: FilmDetail, target: DownloadTarget) -> some View {
        // Subtitle files are attached to their video, not offered on their own.
        let isSubtitleFile = link.link.map { ["vtt", "srt"].contains(URL(string: $0)?.pathExtension.lowercased() ?? "") } ?? false
        return Group {
            if !isSubtitleFile {
                DownloadRow(link: link,
                            onPlay: { url in
                                play(url.absoluteString, detail: detail, season: target.season,
                                     episode: target.episode, row: target.row)
                            },
                            onPlayOffline: { item in
                                if let offline = DownloadManager.shared.playbackItem(for: item) {
                                    playback = offline
                                }
                            },
                            onDownload: { download(link, detail: detail, target: target) })
            }
        }
    }

    private func actorsRow(_ actors: [Actor]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("بازیگران", "Cast")).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(actors.enumerated()), id: \.offset) { _, actor in
                        NavigationLink {
                            ActorView(actorId: actor.id ?? 0, name: actor.name ?? "",
                                      image: actor.image, bio: actor.bio)
                        } label: {
                            VStack(spacing: 6) {
                                RemoteImage(url: URL(string: actor.image ?? ""))
                                    .frame(width: 72, height: 72)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.1)))
                                Text(Localizer.shown(actor.name) ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 82)
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
                    .foregroundStyle(Theme.secondaryText)
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
                SectionTitle(text: "نظرات")
                Spacer()
                NavigationLink {
                    CommentsView(postId: detail.id)
                } label: {
                    Text(detail.comments.isEmpty ? "ثبت نظر" : "همه نظرات (\(detail.totalComments ?? detail.comments.count))")
                        .font(.footnote.weight(.semibold))
                }
            }
            if detail.comments.isEmpty {
                Text("هنوز نظری ثبت نشده است.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
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
        } catch is CancellationError {
            // Superseded or the screen closed: not an error to show.
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
        } catch is CancellationError {
            // Superseded or the screen closed: not an error to show.
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
        } catch is CancellationError {
            // Superseded or the screen closed: not an error to show.
        } catch {
            notice = error.localizedDescription
        }
    }

    /// Checks the account against the site's rules; false when something blocks it.
    private func allowed(_ feature: String, detail: FilmDetail) -> Bool {
        switch appState.access(to: feature, paid: detail.isPaid) {
        case .allowed:
            return true
        case .needsLogin:
            showLogin = true
        case .needsSubscription:
            notice = feature == "download"
                ? "دانلود این محتوا نیاز به اشتراک ویژه دارد."
                : "برای تماشای این محتوا نیاز به اشتراک ویژه دارید."
        case .unavailableInRegion:
            // No playback abroad, and nothing is said about it.
            break
        }
        return false
    }

    private func play(_ link: String, detail: FilmDetail?, season: Int = 0, episode: Int = 0,
                      row: Int = 0, startAt: Double = 0) {
        guard let detail, allowed("playonline", detail: detail) else { return }
        guard var item = playbackItem(link, detail: detail, season: season, episode: episode,
                                      row: row, startAt: startAt)
        else {
            // An empty link means the server hid it: the session is no longer valid.
            showLogin = !appState.isSignedIn
            if appState.isSignedIn { notice = "لینک پخش در دسترس نیست." }
            return
        }
        guard Playback.isNativelyPlayable(item.url) else {
            notice = "این فرمت ویدیو در آیفون پخش نمی‌شود."
            return
        }
        if detail.isSeries { item.upNext = upNext(after: season, episode: episode, detail: detail) }
        AppAnalytics.startedPlayback(id: detail.id, name: detail.displayName,
                                     contentType: detail.isSeries ? "series" : "film")
        playback = item
    }

    private func playbackItem(_ link: String, detail: FilmDetail, season: Int, episode: Int,
                              row: Int, startAt: Double) -> PlaybackItem? {
        guard !link.isEmpty, let url = URL(string: link) else { return nil }
        return PlaybackItem(url: url,
                            title: detail.displayName,
                            postId: detail.id,
                            contentType: detail.isSeries ? "series" : "film",
                            seasonNo: season,
                            episodeNo: episode,
                            movieRowNo: row,
                            startAt: startAt,
                            subtitleURL: subtitleURL(for: link, in: detail),
                            posterURL: detail.posterURL,
                            sources: sources(for: link, in: detail, row: row))
    }

    /// The other qualities of the same video, for the player's quality menu.
    private func sources(for link: String, in detail: FilmDetail, row: Int) -> [PlaybackSource] {
        var options = filmPlayLinks(detail, row: row)
        for season in detail.serialDl {
            for episode in season.episode where episode.onlineLink == link
                || (episode.quality?.available.contains { $0.url == link } ?? false) {
                options = episode.quality?.available ?? []
            }
        }
        let sources = options.compactMap { option in
            URL(string: option.url).map { PlaybackSource(label: option.label, url: $0) }
        }
        return sources.contains { $0.url.absoluteString == link } ? sources : []
    }

    /// The episodes after this one in the same season, for "next episode".
    private func upNext(after season: Int, episode: Int, detail: FilmDetail) -> [PlaybackItem] {
        guard let current = detail.serialDl.enumerated()
            .first(where: { $0.element.number(fallback: $0.offset) == season })?.element
        else { return [] }
        return current.episode.enumerated().compactMap { offset, next in
            let number = next.episodeNumber ?? offset + 1
            guard number > episode, let link = episodePlayLink(next) else { return nil }
            return playbackItem(link, detail: detail, season: season, episode: number, row: 0, startAt: 0)
        }
    }

    private func playTrailer(_ url: URL, detail: FilmDetail) {
        if Playback.isNativelyPlayable(url), !url.pathExtension.isEmpty {
            // postId 0: a trailer has no watch progress.
            playback = PlaybackItem(url: url, title: L("تریلر", "Trailer") + " · \(detail.displayName)", postId: 0,
                                    contentType: "trailer", posterURL: detail.posterURL)
        } else {
            webLink = WebLink(url: url, title: L("تریلر", "Trailer"))
        }
    }

    private func download(_ link: DownloadLink, detail: FilmDetail, target: DownloadTarget) {
        guard allowed("download", detail: detail) else { return }
        guard let address = link.link, !address.isEmpty, let url = URL(string: address) else {
            showLogin = !appState.isSignedIn
            if appState.isSignedIn { notice = "لینک دانلود در دسترس نیست." }
            return
        }
        DownloadManager.shared.start(DownloadItem(
            postId: detail.id,
            title: detail.displayName,
            episodeLabel: target.label,
            posterURL: detail.posterURL,
            remoteURL: url,
            remoteSubtitleURL: subtitleURL(for: address, in: detail),
            quality: [link.quality, link.dlRowInfo?.plainText].compactMap { $0 }.joined(separator: " · "),
            contentType: detail.isSeries ? "series" : "film",
            seasonNo: target.season,
            episodeNo: target.episode,
            movieRowNo: target.row))
        notice = "دانلود شروع شد. پیشرفت آن را در بخش «دانلودها» ببینید."
    }
}

/// Where a download row belongs, for its watch progress and label.
private struct DownloadTarget {
    let row: Int
    let season: Int
    let episode: Int
    let label: String?
}

/// A download link: quality and size, with play and download buttons. The
/// address itself is never shown.
private struct DownloadRow: View {
    let link: DownloadLink
    let onPlay: (URL) -> Void
    let onPlayOffline: (DownloadItem) -> Void
    let onDownload: () -> Void

    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        let url = link.link.flatMap(URL.init(string:))
        let saved = url.flatMap { downloads.item(for: $0) }

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(link.quality ?? "دانلود")
                    .font(.footnote.bold())
                HStack(spacing: 6) {
                    if let info = link.dlRowInfo ?? link.versionLabel {
                        Text(info.plainText).lineLimit(1)
                    }
                    if let size = link.size { Text(size) }
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 4)

            if let url, Playback.isNativelyPlayable(url), saved?.state != .completed {
                iconButton("play.fill") { onPlay(url) }
            }
            stateButton(saved)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func stateButton(_ saved: DownloadItem?) -> some View {
        switch saved?.state {
        case .none:
            iconButton("arrow.down", action: onDownload)
        case .downloading:
            Button { if let saved { downloads.pause(saved.id) } } label: {
                ZStack {
                    Circle().stroke(Theme.surfaceRaised, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.02, saved?.progress ?? 0))
                        .stroke(Theme.accentText, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "pause.fill").font(.caption2)
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        case .paused, .failed:
            iconButton("arrow.clockwise") { if let saved { downloads.resume(saved.id) } }
        case .completed:
            Button { if let saved { onPlayOffline(saved) } } label: {
                Label("آفلاین", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
    }

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote.bold())
                .frame(width: 34, height: 34)
                .background(Theme.surfaceRaised, in: Circle())
                .foregroundStyle(Theme.accentText)
        }
        .buttonStyle(.plain)
    }
}

/// A story that starts at five lines with a "more" toggle.
private struct ExpandableText: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(6)
                .lineLimit(expanded ? nil : 5)
            if text.count > 220 {
                Button(expanded ? L("کمتر", "Less") : L("بیشتر", "More")) {
                    withAnimation { expanded.toggle() }
                }
                .font(.footnote.bold())
            }
        }
    }
}
