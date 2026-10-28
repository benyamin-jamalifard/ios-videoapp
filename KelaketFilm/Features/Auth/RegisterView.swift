import SwiftUI

struct RegisterView: View {
    let onRegistered: (String) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var referralCode = ""
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TextField("نام کاربری", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fieldStyle()
                    TextField("ایمیل", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .fieldStyle()
                    SecureField("رمز عبور", text: $password)
                        .textContentType(.newPassword)
                        .fieldStyle()
                    TextField("کد معرف (اختیاری)", text: $referralCode)
                        .textInputAutocapitalization(.never)
                        .fieldStyle()

                    Button(action: register) {
                        if isLoading { ProgressView().tint(.black) } else { Text("ثبت‌نام") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(username.isEmpty || email.isEmpty || password.isEmpty || isLoading)

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("ثبت‌نام")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("بستن") { dismiss() }
                }
            }
        }
    }

    private func register() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let response = try await appState.api.register(username: username,
                                                               email: email,
                                                               password: password,
                                                               referralCode: referralCode)
                if response.code == "200" {
                    onRegistered(username)
                    dismiss()
                } else {
                    message = response.message ?? "ثبت‌نام ناموفق بود."
                }
            } catch {
                // Validation failures come back as WP_Error with a Persian message.
                message = error.localizedDescription
            }
        }
    }
}
