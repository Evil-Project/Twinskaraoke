import SwiftUI

struct AccountView: View {
    @Environment(MacAuthManager.self) private var auth
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        Group {
            if auth.isLoggedIn {
                signedIn
            } else {
                signInForm
            }
        }
        .navigationTitle("Account")
    }

    private var signedIn: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.appAccent)
            Text(auth.username ?? "Signed in")
                .font(.title2.weight(.semibold))
            Button("Sign Out", role: .destructive) {
                auth.logout()
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var signInForm: some View {
        VStack(spacing: 14) {
            Text("Sign in to Twinskaraoke")
                .font(.title2.weight(.semibold))
            Text("Your favourites and playlists follow your account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
                    .onSubmit(submit)
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)

            if let error = auth.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(width: 280)
            }

            Button(action: submit) {
                if auth.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sign In").frame(width: 100)
                }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(auth.isLoading || username.isEmpty || password.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func submit() {
        guard !auth.isLoading else { return }
        Task {
            await auth.login(username: username, password: password)
            if auth.isLoggedIn { password = "" }
        }
    }
}
