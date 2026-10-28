import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLogin = false
    @State private var showRegister = false
    @State private var webLink: WebLink?

    var body: some View {
        List {
            if appState.isInternational {
                Section {
                    VStack(spacing: 12) {
                        Image("Logo").resizable().scaledToFit().frame(height: 64)
                        Text(Bundle.main.displayName).font(.headline)
                        Text("Browse our catalogue of movies and series. Streaming and downloads are available in Iran only.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else if appState.isSignedIn {
                Section {
                    NavigationLink { EditProfileView() } label: {
                        HStack(spacing: 14) {
                            RemoteImage(url: URL(string: appState.user?.avatar ?? ""))
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(appState.user?.displayName ?? "کاربر")
                                    .font(.headline)
                                if let detail = appState.user?.mobile ?? appState.user?.email {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if appState.config.activeVip {
                    Section("اشتراک") {
                        LabeledContent("وضعیت", value: appState.subscription?.subStateFa ?? "—")
                        if let sub = appState.subscription, sub.hasActiveSub, let days = sub.subDaysRemain {
                            LabeledContent("روزهای باقی‌مانده", value: "\(days)")
                        }
                        if appState.config.kelaketappShowTrans {
                            NavigationLink { VipTransactionsView() } label: {
                                Label("تراکنش‌های اشتراک", systemImage: "creditcard")
                            }
                        }
                    }
                }

                if appState.config.walletEnabled || appState.config.referralEnabled {
                    Section {
                        if appState.config.walletEnabled {
                            NavigationLink { WalletView() } label: {
                                Label("کیف پول", systemImage: "wallet.pass")
                            }
                        }
                        if appState.config.referralEnabled {
                            NavigationLink { ReferralView() } label: {
                                Label("دعوت از دوستان", systemImage: "gift")
                            }
                        }
                    }
                }

                Section {
                    if appState.config.kelaketappShowMylist {
                        NavigationLink { WatchlistView() } label: {
                            Label("لیست تماشا", systemImage: "bookmark")
                        }
                    }
                    NavigationLink { MyListsView() } label: {
                        Label("لیست‌های من", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink { NotificationsView() } label: {
                        Label("اعلان‌ها", systemImage: "bell")
                    }
                    if appState.config.profileShowTickets {
                        NavigationLink { TicketsView() } label: {
                            Label("پشتیبانی", systemImage: "bubble.left.and.bubble.right")
                        }
                    }
                    if appState.config.profileShowRequestFilm {
                        NavigationLink { FilmRequestsView() } label: {
                            Label("درخواست فیلم", systemImage: "film.stack")
                        }
                    }
                }

                Section {
                    if appState.config.profileShowActiveSession {
                        NavigationLink { ActiveSessionsView() } label: {
                            Label("دستگاه‌های فعال", systemImage: "laptopcomputer.and.iphone")
                        }
                    }
                    Button("خروج از حساب", role: .destructive) { appState.signOut() }
                }
            } else {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 96, height: 96)
                            .background(Theme.surfaceRaised, in: Circle())
                        Text("برای دسترسی به امکانات حساب کاربری، وارد شوید")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button("ثبت نام") { showRegister = true }
                                .buttonStyle(PrimaryButtonStyle())
                            Button { showLogin = true } label: {
                                Text("ورود")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                        .stroke(Theme.muted.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                Section {
                    NavigationLink { NotificationsView() } label: {
                        Label("اعلان‌ها", systemImage: "bell")
                    }
                }
            }

            // Kept for the App Store (guideline 5.1.1 asks for a reachable privacy
            // policy); they open inside the app, so the addresses stay hidden.
            Section {
                if let link = appState.config.rulesLink, let url = URL(string: link) {
                    pageRow(L("قوانین", "Terms of use"), icon: "doc.text", url: url)
                }
                if let link = appState.config.privacyLink, let url = URL(string: link) {
                    pageRow(L("حریم خصوصی", "Privacy policy"), icon: "hand.raised", url: url)
                }
                if !appState.isInternational {
                    if let telegram = appState.config.telegram, let url = URL(string: telegram) {
                        pageRow("تلگرام", icon: "paperplane", url: url)
                    }
                    if let instagram = appState.config.instagram, let url = URL(string: instagram) {
                        pageRow("اینستاگرام", icon: "camera", url: url)
                    }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("پروفایل", "More"))
        .refreshable { await appState.refreshSubscription() }
        .sheet(item: $webLink) { link in WebPageView(url: link.url, title: link.title) }
        .sheet(isPresented: $showLogin) { LoginView().environmentObject(appState) }
        .sheet(isPresented: $showRegister) {
            RegisterView { _ in
                // Open the login form once the register sheet has gone.
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    showLogin = true
                }
            }
            .environmentObject(appState)
        }
    }

    private func pageRow(_ title: String, icon: String, url: URL) -> some View {
        Button { webLink = WebLink(url: url, title: title) } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
