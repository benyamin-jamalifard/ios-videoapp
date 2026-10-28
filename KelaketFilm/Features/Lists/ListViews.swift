import SwiftUI

/// Lists other users have made public.
struct PublicListsView: View {
    @StateObject private var pager = Pager<UserList> { page in
        let result = try await APIClient.shared.publicLists(page: page)
        return (result.lists, page < (result.pages ?? page))
    }

    var body: some View {
        List {
            ForEach(Array(pager.items.enumerated()), id: \.offset) { index, list in
                NavigationLink {
                    ListDetailView(list: list, isMine: false)
                } label: {
                    ListRow(list: list)
                }
                .listRowBackground(Theme.surface)
                .onAppear {
                    if index == pager.items.count - 1 { Task { await pager.loadMore() } }
                }
            }
            if pager.isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if pager.isLoaded && pager.items.isEmpty {
                Text(pager.error ?? "هنوز لیستی منتشر نشده است.")
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("لیست‌های کاربران")
        .task { if !pager.isLoaded { await pager.reload() } }
        .refreshable { await pager.reload() }
    }
}

/// The signed-in user's own lists, with create / edit / delete.
struct MyListsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var lists: [UserList]?
    @State private var editing: ListEditorTarget?
    @State private var notice: String?

    var body: some View {
        List {
            if let lists {
                if lists.isEmpty {
                    Text("هنوز لیستی نساخته‌اید. از دکمه + یا صفحه هر فیلم شروع کنید.")
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Color.clear)
                }
                ForEach(lists) { list in
                    NavigationLink {
                        ListDetailView(list: list, isMine: true)
                    } label: {
                        ListRow(list: list)
                    }
                    .listRowBackground(Theme.surface)
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await delete(list) }
                        } label: {
                            Label("حذف", systemImage: "trash")
                        }
                        Button {
                            editing = .edit(list)
                        } label: {
                            Label("ویرایش", systemImage: "pencil")
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("لیست‌های من")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .create(films: []) } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editing) { target in
            ListEditor(target: target) { await load() }
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil },
                                                  set: { if !$0 { notice = nil } })) {
            Button("باشه", role: .cancel) {}
        }
    }

    private func load() async {
        do {
            lists = try await appState.api.myLists()
        } catch {
            if lists == nil { lists = [] }
            notice = error.localizedDescription
        }
    }

    private func delete(_ list: UserList) async {
        do {
            try await appState.api.deleteList(id: list.id)
            lists?.removeAll { $0.id == list.id }
        } catch {
            notice = error.localizedDescription
        }
    }
}

struct ListDetailView: View {
    let list: UserList
    let isMine: Bool

    @State private var films: [Post]
    @State private var notice: String?

    init(list: UserList, isMine: Bool) {
        self.list = list
        self.isMine = isMine
        _films = State(initialValue: list.films)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let author = list.userName {
                    Label(author, systemImage: "person").font(.caption).foregroundStyle(Theme.muted)
                }
                if let description = list.listDesc {
                    Text(description.plainText).font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top])

            if films.isEmpty {
                Text("این لیست خالی است.").foregroundStyle(Theme.muted).padding(.top, 40)
            } else if isMine {
                // Own lists: long-press a poster to remove it.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 16) {
                    ForEach(films) { post in
                        NavigationLink(value: FilmRoute(id: post.id)) {
                            PosterCard(post: post, width: 105)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await remove(post) }
                            } label: {
                                Label("حذف از لیست", systemImage: "minus.circle")
                            }
                        }
                    }
                }
                .padding()
            } else {
                PosterGrid(posts: films)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(list.name ?? "لیست")
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil },
                                                  set: { if !$0 { notice = nil } })) {
            Button("باشه", role: .cancel) {}
        }
    }

    private func remove(_ post: Post) async {
        do {
            try await APIClient.shared.updateListItems(id: list.id, mode: "remove", films: [post.id])
            films.removeAll { $0.id == post.id }
        } catch {
            notice = error.localizedDescription
        }
    }
}

private struct ListRow: View {
    let list: UserList

    var body: some View {
        HStack(spacing: 12) {
            // Up to three overlapping posters as a cover.
            ZStack(alignment: .leading) {
                ForEach(Array(list.films.prefix(3).enumerated().reversed()), id: \.offset) { index, post in
                    RemoteImage(url: post.posterURL)
                        .frame(width: 40, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .offset(x: CGFloat(index) * 14)
                }
            }
            .frame(width: 70, height: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(list.name ?? "").font(.subheadline.bold())
                    if list.isPrivate {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
                Text("\(list.films.count) عنوان" + (list.userName.map { " · \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

enum ListEditorTarget: Identifiable {
    case create(films: [Int])
    case edit(UserList)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let list): return "edit-\(list.id)"
        }
    }
}

struct ListEditor: View {
    let target: ListEditorTarget
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("نام لیست (حداقل ۶ حرف)", text: $name)
                Section("توضیحات") {
                    TextEditor(text: $description).frame(minHeight: 100)
                }
                Toggle("خصوصی (فقط خودم ببینم)", isOn: $isPrivate)
                if let error {
                    Text(error).foregroundStyle(.orange).font(.footnote)
                }
            }
            .navigationTitle(isEditing ? "ویرایش لیست" : "لیست جدید")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("انصراف") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("ذخیره", action: save)
                            .disabled(name.trimmingCharacters(in: .whitespaces).count < 6)
                    }
                }
            }
        }
        .onAppear {
            if case .edit(let list) = target {
                name = list.name ?? ""
                description = list.listDesc ?? ""
                isPrivate = list.isPrivate
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = target { return true }
        return false
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                switch target {
                case .create(let films):
                    try await APIClient.shared.createList(name: name, description: description,
                                                          isPrivate: isPrivate, films: films)
                case .edit(let list):
                    try await APIClient.shared.updateList(id: list.id, name: name,
                                                          description: description, isPrivate: isPrivate)
                }
                await onSaved()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// From a film page: toggle the film in each of the user's lists, or start a new list with it.
struct AddToListSheet: View {
    let postId: Int

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var lists: [UserList]?
    @State private var busy: Int?
    @State private var creating: ListEditorTarget?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Button {
                    creating = .create(films: [postId])
                } label: {
                    Label("لیست جدید با این عنوان", systemImage: "plus")
                }

                if let lists {
                    ForEach(lists) { list in
                        let contains = list.films.contains { $0.id == postId }
                        Button {
                            Task { await toggle(list, contains: contains) }
                        } label: {
                            HStack {
                                Text(list.name ?? "")
                                Spacer()
                                if busy == list.id {
                                    ProgressView()
                                } else if contains {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accentText)
                                }
                            }
                        }
                        .disabled(busy != nil)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }

                if let error {
                    Text(error).foregroundStyle(.orange).font(.footnote)
                }
            }
            .navigationTitle("افزودن به لیست")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تمام") { dismiss() }
                }
            }
            .task { await load() }
            .sheet(item: $creating) { target in
                ListEditor(target: target) { await load() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        do {
            lists = try await appState.api.myLists()
        } catch {
            lists = lists ?? []
            self.error = error.localizedDescription
        }
    }

    private func toggle(_ list: UserList, contains: Bool) async {
        busy = list.id
        defer { busy = nil }
        do {
            try await appState.api.updateListItems(id: list.id, mode: contains ? "remove" : "add",
                                                   films: [postId])
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
