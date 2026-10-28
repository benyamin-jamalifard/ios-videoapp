import SwiftUI

struct TicketsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tickets: [Ticket]?
    @State private var error: String?
    @State private var showNewTicket = false
    @State private var notice: String?

    private var needsSubscription: Bool {
        appState.config.appTicketNeedVip && !(appState.subscription?.hasActiveSub ?? false)
    }

    var body: some View {
        List {
            if let tickets {
                if tickets.isEmpty {
                    Text("تیکتی ثبت نکرده‌اید.")
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Color.clear)
                }
                ForEach(tickets) { ticket in
                    NavigationLink {
                        TicketChatView(ticket: ticket)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ticket.subject ?? "تیکت #\(ticket.id)").font(.subheadline.bold())
                            HStack {
                                if let department = ticket.department { Text(department) }
                                if let date = ticket.createdAt { Text(date) }
                                Spacer()
                                if let status = ticket.statusLabel {
                                    Text(status)
                                        .foregroundStyle(ticket.status == 2 ? .green : Theme.accent)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            } else if let error {
                Text(error).foregroundStyle(.orange).listRowBackground(Color.clear)
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("پشتیبانی")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if needsSubscription {
                        notice = "ارسال تیکت فقط برای کاربران دارای اشتراک فعال است."
                    } else {
                        showNewTicket = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showNewTicket) {
            NewTicketView { await load() }
                .environmentObject(appState)
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil },
                                                  set: { if !$0 { notice = nil } })) {
            Button("باشه", role: .cancel) {}
        }
    }

    private func load() async {
        do {
            tickets = try await appState.api.tickets()
            error = nil
        } catch {
            if tickets == nil { self.error = error.localizedDescription }
        }
    }
}

private struct NewTicketView: View {
    let onCreated: () async -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var department = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("موضوع", text: $title)
                if !appState.config.ticketDeps.isEmpty {
                    Picker("دپارتمان", selection: $department) {
                        ForEach(appState.config.ticketDeps, id: \.name) { dep in
                            Text(dep.name).tag(dep.name)
                        }
                    }
                }
                Section("متن پیام") {
                    TextEditor(text: $message).frame(minHeight: 160)
                }
                if let error {
                    Text(error).foregroundStyle(.orange).font(.footnote)
                }
            }
            .navigationTitle("تیکت جدید")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("انصراف") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("ارسال", action: send)
                            .disabled(title.isEmpty || message.isEmpty)
                    }
                }
            }
            .onAppear {
                if department.isEmpty { department = appState.config.ticketDeps.first?.name ?? "" }
            }
        }
    }

    private func send() {
        Task {
            isSending = true
            defer { isSending = false }
            do {
                let response = try await appState.api.createTicket(title: title,
                                                                   department: department,
                                                                   message: message)
                if response.success {
                    await onCreated()
                    dismiss()
                } else {
                    error = response.text ?? "ارسال تیکت ناموفق بود."
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct TicketChatView: View {
    let ticket: Ticket

    @EnvironmentObject private var appState: AppState
    @State private var messages: [TicketMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            if let error {
                Text(error).font(.footnote).foregroundStyle(.orange).padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("پیام خود را بنویسید", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .fieldStyle()
                Button(action: send) {
                    if isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill").font(.title3)
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .padding(.bottom, 12)
            }
            .padding()
            .background(Theme.surface)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(ticket.subject ?? "تیکت")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func bubble(_ message: TicketMessage) -> some View {
        let isMine = message.userId == appState.userId
        return VStack(alignment: isMine ? .leading : .trailing, spacing: 4) {
            Text(message.msg?.plainText ?? "")
                .padding(12)
                .background(isMine ? Theme.accent.opacity(0.25) : Theme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            if let date = message.createdAt {
                Text(date).font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        // In RTL, leading is the right edge: the user's own messages sit on the right.
        .frame(maxWidth: .infinity, alignment: isMine ? .leading : .trailing)
    }

    private func load() async {
        do {
            messages = try await appState.api.ticketMessages(ticketId: ticket.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            isSending = true
            defer { isSending = false }
            do {
                let response = try await appState.api.replyToTicket(ticketId: ticket.id, message: text)
                if response.success {
                    draft = ""
                    await load()
                } else {
                    error = response.text ?? "ارسال پیام ناموفق بود."
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
