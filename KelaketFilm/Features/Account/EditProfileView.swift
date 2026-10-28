import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var avatars: [AvatarOptions.DefaultAvatar] = []
    @State private var selectedAvatar: Int?
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        Form {
            if !avatars.isEmpty {
                Section("آواتار") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(avatars) { avatar in
                                Button { selectedAvatar = avatar.id } label: {
                                    RemoteImage(url: URL(string: avatar.url ?? ""))
                                        .frame(width: 56, height: 56)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Theme.accent,
                                                                 lineWidth: selectedAvatar == avatar.id ? 3 : 0))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("اطلاعات") {
                TextField("نام نمایشی", text: $name)
                TextField("ایمیل", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                SecureField("رمز عبور جدید", text: $password)
                    .textContentType(.newPassword)
            } header: {
                Text("تغییر رمز عبور")
            } footer: {
                Text("خالی بگذارید تا رمز تغییر نکند. پس از تغییر رمز، از همه دستگاه‌ها خارج می‌شوید و باید دوباره وارد شوید.")
            }

            if let message {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("ویرایش پروفایل")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("ذخیره", action: save)
                }
            }
        }
        .onAppear {
            name = appState.user?.displayName ?? ""
            email = appState.user?.email ?? ""
        }
        .task {
            guard let options = try? await appState.api.avatarOptions() else { return }
            avatars = options.defaultAvatars
            selectedAvatar = options.currentAvatar?.defaultAvatarId
        }
    }

    private func save() {
        guard let userId = appState.userId else {
            message = "برای ویرایش دوباره وارد حساب شوید."
            return
        }
        // An empty `newEmail` leaves the address alone, so only send it when it changed.
        let newEmail = email == (appState.user?.email ?? "") ? "" : email
        let changedPassword = !password.isEmpty
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                let response = try await appState.api.editProfile(userId: userId,
                                                                  name: name,
                                                                  email: newEmail,
                                                                  password: changedPassword ? password : nil,
                                                                  defaultAvatarId: selectedAvatar)
                guard response.code == "200" else {
                    message = response.message ?? "ذخیره نشد."
                    return
                }
                if changedPassword {
                    // The server revoked this token along with all others.
                    appState.signOut()
                } else {
                    appState.updateUser(displayName: name, email: email, avatar: response.avatar)
                }
                dismiss()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// Sends a WordPress password-reset email.
struct ForgotPasswordView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isSending = false
    @State private var message: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ایمیل حساب کاربری", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("لینک تعیین رمز جدید به این ایمیل فرستاده می‌شود.")
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(sent ? .green : .orange)
                }
            }
            .navigationTitle("فراموشی رمز عبور")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("بستن") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("ارسال", action: send)
                            .disabled(!email.contains("@") || sent)
                    }
                }
            }
        }
    }

    private func send() {
        Task {
            isSending = true
            defer { isSending = false }
            do {
                let response = try await appState.api.requestPasswordReset(email: email)
                // Success is `{success: true, data: {sent: true, msg}}`.
                sent = response.success && !response.error
                message = response.text ?? (sent ? "ایمیل ارسال شد." : "ارسال نشد.")
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
