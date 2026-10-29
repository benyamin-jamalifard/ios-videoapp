import SwiftUI

/// The theme's "گزارش مشکل" form: a broken link, subtitle or playback problem
/// reported to the site admins for this title.
struct ReportProblemSheet: View {
    let postId: Int
    let title: String

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?
    @State private var details = ""
    @State private var name = ""
    @State private var isSending = false
    @State private var result: (text: String, success: Bool)?

    private static let problems = [
        "لینک دانلود کار نمی‌کند",
        "پخش آنلاین کار نمی‌کند",
        "زیرنویس مشکل دارد یا هماهنگ نیست",
        "کیفیت تصویر یا صدا مشکل دارد",
        "قسمت یا فصل جابه‌جا یا ناقص است",
        "اطلاعات فیلم اشتباه است",
    ]

    private var canSend: Bool {
        !isSending && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (problem != nil || !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Self.problems, id: \.self) { item in
                        Button {
                            problem = problem == item ? nil : item
                        } label: {
                            HStack {
                                Text(item).foregroundStyle(.primary)
                                Spacer()
                                if problem == item {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accentText)
                                }
                            }
                        }
                    }
                } header: {
                    Text("مشکل چیست؟")
                }

                Section {
                    TextEditor(text: $details)
                        .frame(minHeight: 110)
                } header: {
                    Text("توضیحات")
                } footer: {
                    Text("مثلاً کیفیت، نسخه (دوبله یا زیرنویس) یا شماره قسمت را بنویسید.")
                }

                Section {
                    TextField("نام شما", text: $name)
                        .textContentType(.name)
                }

                if let result {
                    Section {
                        Label(result.text, systemImage: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(result.success ? .green : .orange)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("گزارش مشکل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("انصراف") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("ارسال") { Task { await send() } }
                            .disabled(!canSend)
                    }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            if name.isEmpty { name = appState.user?.displayName ?? "" }
        }
    }

    private func send() async {
        isSending = true
        result = nil
        let text = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = [problem, text.isEmpty ? nil : text, "— \(title) · ارسال از اپ iOS"]
            .compactMap { $0 }
            .joined(separator: "\n")
        do {
            let message = try await appState.api.reportProblem(
                postId: postId, name: name.trimmingCharacters(in: .whitespaces), description: description)
            result = (message, true)
            isSending = false
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            dismiss()
        } catch is CancellationError {
            // Superseded or the screen closed: not an error to show.
        } catch {
            result = (error.localizedDescription, false)
            isSending = false
        }
    }
}

/// The small flag button above the links, as on the site.
struct ReportProblemButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("گزارش مشکل", systemImage: "flag")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.surfaceRaised, in: Capsule())
        }
        .foregroundStyle(Theme.secondaryText)
    }
}
