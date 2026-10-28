import SwiftUI

struct WalletView: View {
    @EnvironmentObject private var appState: AppState
    @State private var balance: String?
    @State private var entries: [WalletEntry] = []
    @State private var page = 0
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("موجودی کیف پول").font(.footnote).foregroundStyle(Theme.muted)
                    Text(Money.format(balance)).font(.title.bold()).foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Theme.surface)
            }

            Section("تراکنش‌ها") {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    EntryRow(entry: entry)
                        .listRowBackground(Theme.surface)
                        .onAppear {
                            if index == entries.count - 1 { Task { await loadMore() } }
                        }
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                } else if let error {
                    Text(error).foregroundStyle(.orange).listRowBackground(Color.clear)
                } else if page > 0 && entries.isEmpty {
                    Text("تراکنشی ثبت نشده است.").foregroundStyle(Theme.muted).listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("کیف پول")
        .task { if page == 0 { await reload() } }
        .refreshable { await reload() }
    }

    private func reload() async {
        page = 0
        totalPages = 1
        entries = []
        await loadMore()
    }

    private func loadMore() async {
        guard !isLoading, page < totalPages else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appState.api.wallet(page: page + 1)
            page += 1
            balance = result.balance ?? balance
            entries += result.items
            totalPages = result.pagination?.totalPages ?? page
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ReferralView: View {
    @EnvironmentObject private var appState: AppState
    @State private var info: ReferralPage?
    @State private var entries: [WalletEntry] = []
    @State private var page = 0
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        List {
            if let info {
                Section {
                    if let code = info.code {
                        HStack {
                            Text("کد معرف").foregroundStyle(Theme.muted)
                            Spacer()
                            Text(code).font(.headline.monospaced())
                        }
                    }
                    if let link = info.inviteLink, let url = URL(string: link) {
                        ShareLink(item: url, message: Text("با این لینک در کلاکت فیلم ثبت‌نام کن")) {
                            Label("اشتراک‌گذاری لینک دعوت", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.string = link
                            copied = true
                        } label: {
                            Label(copied ? "کپی شد" : "کپی لینک دعوت",
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                    }
                } footer: {
                    if let percent = info.commissionPercent {
                        Text("از هر خرید دوستانی که دعوت می‌کنید \(percent)٪ به کیف پول شما اضافه می‌شود.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    stat("دعوت‌شده‌ها", value: info.referredUsersCount.map { "\($0)" } ?? "۰")
                    stat("مجموع درآمد", value: Money.format(info.totalEarnings))
                }
                .listRowBackground(Theme.surface)
            }

            Section("درآمدها") {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    EntryRow(entry: entry)
                        .listRowBackground(Theme.surface)
                        .onAppear {
                            if index == entries.count - 1 { Task { await loadMore() } }
                        }
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                } else if let error {
                    Text(error).foregroundStyle(.orange).listRowBackground(Color.clear)
                } else if page > 0 && entries.isEmpty {
                    Text("هنوز کسی با کد شما خرید نکرده است.")
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("دعوت از دوستان")
        .task { if page == 0 { await reload() } }
        .refreshable { await reload() }
    }

    private func stat(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).bold()
        }
    }

    private func reload() async {
        page = 0
        totalPages = 1
        entries = []
        await loadMore()
    }

    private func loadMore() async {
        guard !isLoading, page < totalPages else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appState.api.referral(page: page + 1)
            page += 1
            if page == 1 { info = result }
            entries += result.items
            totalPages = result.pagination?.totalPages ?? page
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// VIP purchases. The route has no reliable paging, so only the first page is shown.
struct VipTransactionsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [VipPayment]?
    @State private var error: String?

    var body: some View {
        List {
            if let items {
                if items.isEmpty {
                    Text("خریدی ثبت نشده است.").foregroundStyle(Theme.muted).listRowBackground(Color.clear)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title).font(.subheadline.bold())
                            Spacer()
                            Text(Money.format(item.total)).font(.subheadline)
                        }
                        HStack {
                            if let status = item.status { Text(status) }
                            if let gateway = item.gateway { Text(gateway) }
                            Spacer()
                            if let when = item.when { Text(when) }
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        if let hash = item.transactionHash {
                            Text(hash).font(.caption2.monospaced()).foregroundStyle(Theme.muted).lineLimit(1)
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
        .navigationTitle("تراکنش‌های اشتراک")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            items = try await appState.api.vipTransactions(page: 1)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct EntryRow: View {
    let entry: WalletEntry

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title ?? (entry.isDebit ? "برداشت" : "واریز")).font(.subheadline)
                if let date = entry.createdAt {
                    Text(date).font(.caption2).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            Text(Money.format(entry.amount))
                .font(.subheadline.bold())
                .foregroundStyle(entry.isDebit ? .red : .green)
        }
    }
}

/// Amounts arrive as plain numbers in tomans.
enum Money {
    static func format(_ amount: String?) -> String {
        guard let amount, !amount.isEmpty else { return "۰ تومان" }
        let digits = amount.latinDigits.replacingOccurrences(of: ",", with: "")
        guard let value = Double(digits) else { return amount }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "fa_IR")
        formatter.maximumFractionDigits = 0
        let text = formatter.string(from: NSNumber(value: abs(value))) ?? amount
        return "\(text) تومان"
    }
}
