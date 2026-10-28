import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLogin = false

    var body: some View {
        List {
            if appState.isSignedIn {
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
                                        .foregroundStyle(Theme.muted)
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
                    Button("ورود یا ثبت‌نام") { showLogin = true }
                    NavigationLink { NotificationsView() } label: {
                        Label("اعلان‌ها", systemImage: "bell")
                    }
                }
            }

            Section {
                if let link = appState.config.rulesLink, let url = URL(string: link) {
                    Link("قوانین", destination: url)
                }
                if let link = appState.config.privacyLink, let url = URL(string: link) {
                    Link("حریم خصوصی", destination: url)
                }
                if let telegram = appState.config.telegram, let url = URL(string: telegram) {
                    Link("تلگرام", destination: url)
                }
                if let instagram = appState.config.instagram, let url = URL(string: instagram) {
                    Link("اینستاگرام", destination: url)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("پروفایل")
        .refreshable { await appState.refreshSubscription() }
        .sheet(isPresented: $showLogin) { LoginView().environmentObject(appState) }
    }
}
