import SwiftUI

struct SignInView: View {
    let auth: AuthModel

    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        if busy { ProgressView() } else { Text("Sign In") }
                    }
                    .disabled(busy || email.isEmpty || password.isEmpty)
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Activity Timers")
        }
    }

    private func signIn() async {
        busy = true
        defer { busy = false }
        do {
            try await auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
