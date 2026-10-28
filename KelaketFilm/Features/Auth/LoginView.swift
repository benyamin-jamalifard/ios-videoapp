import SwiftUI

/// Sign-in sheet. Starts with the method chosen in the plugin settings
/// (`auth_method`) and offers the other one when `second_login_method` is on.
struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var useOTP = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accentText)
                        .padding(.top, 32)

                    if useOTP {
                        OTPLoginForm(onSuccess: finish)
                    } else {
                        PasswordLoginForm(onSuccess: finish)
                    }

                    if appState.config.secondLoginMethod {
                        Button(useOTP ? "ورود با نام کاربری و رمز عبور" : "ورود با شماره موبایل") {
                            withAnimation { useOTP.toggle() }
                        }
                        .font(.footnote)
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("ورود به حساب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("بستن") { dismiss() }
                }
            }
        }
        .onAppear { useOTP = appState.config.usesOTP }
    }

    private func finish(_ response: AuthResponse) {
        appState.signIn(with: response)
        dismiss()
    }
}

private struct OTPLoginForm: View {
    let onSuccess: (AuthResponse) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var message: String?

    private var normalizedPhone: String { phone.latinDigits.filter(\.isNumber) }
    private var phoneIsValid: Bool { normalizedPhone.count == 11 && normalizedPhone.hasPrefix("09") }

    var body: some View {
        VStack(spacing: 16) {
            if !codeSent {
                Text("شماره موبایل خود را وارد کنید")
                    .foregroundStyle(Theme.muted)
                TextField("۰۹۱۲۱۲۳۴۵۶۷", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .fieldStyle()
                Button(action: requestCode) {
                    progressLabel("دریافت کد تایید")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!phoneIsValid || isLoading)
            } else {
                Text("کد ارسال شده به \(normalizedPhone) را وارد کنید")
                    .foregroundStyle(Theme.muted)
                TextField("کد ۶ رقمی", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .fieldStyle()
                Button(action: verifyCode) {
                    progressLabel("ورود")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(code.latinDigits.count < 4 || isLoading)

                Button("تغییر شماره") {
                    codeSent = false
                    code = ""
                    message = nil
                }
                .font(.footnote)
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func progressLabel(_ title: String) -> some View {
        if isLoading { ProgressView().tint(.white) } else { Text(title) }
    }

    private func requestCode() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let response = try await appState.api.requestOTP(phone: normalizedPhone)
                if response.code == "201" {
                    codeSent = true
                    message = nil
                } else {
                    // -1 is the 2-minute rate limit; its message says how long to wait.
                    message = response.message ?? "ارسال کد ناموفق بود."
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func verifyCode() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let response = try await appState.api.verifyOTP(phone: normalizedPhone,
                                                                code: code.latinDigits)
                if response.token != nil {
                    onSuccess(response)
                } else {
                    message = response.message ?? "کد وارد شده صحیح نیست."
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

private struct PasswordLoginForm: View {
    let onSuccess: (AuthResponse) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var message: String?
    @State private var showRegister = false
    @State private var showForgotPassword = false

    var body: some View {
        VStack(spacing: 16) {
            TextField("نام کاربری، ایمیل یا موبایل", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .fieldStyle()
            SecureField("رمز عبور", text: $password)
                .textContentType(.password)
                .fieldStyle()

            Button(action: login) {
                if isLoading { ProgressView().tint(.white) } else { Text("ورود") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(username.isEmpty || password.isEmpty || isLoading)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("رمز را فراموش کرده‌اید؟") { showForgotPassword = true }
                Spacer()
                Button("ثبت‌نام") { showRegister = true }
            }
            .font(.footnote)
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView().environmentObject(appState)
        }
        .sheet(isPresented: $showRegister) {
            RegisterView { registeredUsername in
                username = registeredUsername
                message = "ثبت‌نام انجام شد؛ اکنون وارد شوید."
            }
            .environmentObject(appState)
        }
    }

    private func login() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let response = try await appState.api.login(username: username.latinDigits,
                                                            password: password)
                if response.token != nil {
                    onSuccess(response)
                } else {
                    message = response.message ?? "ورود ناموفق بود."
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

extension View {
    func fieldStyle() -> some View {
        padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
