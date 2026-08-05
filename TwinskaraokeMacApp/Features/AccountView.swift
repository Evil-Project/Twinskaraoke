import SwiftUI

struct AccountView: View {
    @Environment(MacAuthManager.self) private var auth
    @State private var username = ""
    @State private var password = ""
    /// QR pairing is the default: it's the fastest path in when the phone app
    /// is already signed in, same reasoning as tvOS.
    @State private var usePasswordSignIn = false

    var body: some View {
        Group {
            if auth.isLoggedIn {
                signedIn
            } else if usePasswordSignIn {
                signInForm
            } else {
                QRSignInPanel(auth: auth) {
                    usePasswordSignIn = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Account")
    }

    private var signedIn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ProfileHeader(auth: auth)

                if let error = auth.profileError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                if let limits = auth.uploadLimits {
                    UploadLimitsSection(limits: limits)
                }

                if !auth.badges.isEmpty {
                    BadgesSection(badges: auth.badges)
                }

                HStack {
                    Button("Sign Out", role: .destructive) { auth.logout() }
                    Spacer()
                    Button {
                        Task { await auth.refreshAccount() }
                    } label: {
                        if auth.isRefreshingProfile {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(auth.isRefreshingProfile)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await auth.refreshAccount() }
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

            HStack(spacing: 8) {
                VStack { Divider() }
                Text("or").font(.caption).foregroundStyle(.secondary)
                VStack { Divider() }
            }
            .frame(width: 280)

            Button {
                Task { await auth.loginWithDiscord() }
            } label: {
                Label("Sign in with Discord", systemImage: "bubble.left.and.bubble.right.fill")
                    .frame(width: 200)
            }
            .controlSize(.large)
            .disabled(auth.isLoading)

            Button("Scan a code instead") {
                usePasswordSignIn = false
            }
            .buttonStyle(.link)
            .disabled(auth.isLoading)
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
