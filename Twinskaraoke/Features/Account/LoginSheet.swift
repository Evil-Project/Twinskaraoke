import SDWebImageSwiftUI
import SwiftUI

struct LoginSheet: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @FocusState private var focus: LoginField?
    private enum LoginField: Hashable { case username, password }
    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasEnteredCredentials: Bool {
        !trimmedUsername.isEmpty && !password.isEmpty
    }

    private var canSubmit: Bool {
        hasEnteredCredentials && !auth.isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    credentialsCard
                    if let err = auth.errorMessage, !err.isEmpty {
                        errorBanner(err)
                            .transition(errorTransition)
                    }
                    signInButton
                    divider
                    discordButton
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .smoothScrolling()
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassXButton(action: { dismiss() })
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: auth.isLoggedIn) { _, isLoggedIn in
                if isLoggedIn { dismiss() }
            }
            .onChange(of: auth.errorMessage ?? "") { _, message in
                if !message.isEmpty { AppHaptic.error.play() }
            }
            .animation(
                reduceMotion ? nil : AppMotion.quick,
                value: auth.errorMessage ?? ""
            )
            .animation(
                reduceMotion ? nil : AppMotion.quick,
                value: auth.isLoading
            )
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            appLogo
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Sign in to Twinskaraoke")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("Access your library, favorites, and playlists across devices.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var appLogo: some View {
        if !AppLogoData.shared.isEmpty {
            AnimatedImage(data: AppLogoData.shared)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .transaction { $0.animation = nil }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(ProfileTheme.radialGradient)
                Image(systemName: "music.mic")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
            }
        }
    }

    private var credentialsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            Divider().padding(.leading, 50)
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Group {
                    if showPassword {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { signIn() }
                Button {
                    AppHaptic.selection.play()
                    showPassword.toggle()
                } label: {
                    Group {
                        if #available(iOS 17.0, *) {
                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                .contentTransition(.symbolEffect(.replace))
                        } else {
                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.88, dim: 0.72))
                .accessibilityLabel(showPassword ? "Hide Password" : "Show Password")
                .accessibilityValue(showPassword ? "Visible" : "Hidden")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    focus == nil ? Color.clear : Color.appAccent.opacity(0.38),
                    lineWidth: 1.2
                )
        }
        .animation(
            reduceMotion ? nil : AppMotion.snap,
            value: focus
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.appAccent)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.appAccent)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.appAccent.opacity(0.10))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sign-in error")
        .accessibilityValue(message)
    }

    private var signInButton: some View {
        Button(action: signIn) {
            ZStack {
                if auth.isLoading {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Text("Sign In")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(ProfileTheme.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(hasEnteredCredentials ? 1 : 0.5)
        }
        .disabled(!canSubmit)
        .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.78))
        .accessibilityLabel(auth.isLoading ? "Signing In" : "Sign In")
        .accessibilityValue(canSubmit ? "Ready" : "Username and password required")
        .accessibilityHint("Signs in with your Twinskaraoke account.")
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
            Text("OR")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
        }
    }

    private var discordButton: some View {
        Button {
            guard !auth.isLoading else { return }
            AppHaptic.medium.play()
            Task { await auth.loginWithDiscord() }
        } label: {
            HStack(spacing: 10) {
                DiscordIcon(size: 20, color: .white)
                Text("Continue with Discord")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(hex: "5865F2"))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(auth.isLoading)
        .buttonStyle(PressableButtonStyle(scale: 0.97, dim: 0.78))
        .accessibilityLabel("Continue with Discord")
        .accessibilityValue(auth.isLoading ? "Unavailable while signing in" : "Ready")
        .accessibilityHint("Opens Discord sign-in.")
    }

    private var footer: some View {
        Text("By continuing, you agree to Twinskaraoke's Terms of Service and Privacy Policy.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }

    private func signIn() {
        guard canSubmit else {
            AppHaptic.warning.play()
            focus = trimmedUsername.isEmpty ? .username : .password
            return
        }
        AppHaptic.medium.play()
        focus = nil
        Task { await auth.login(username: trimmedUsername, password: password) }
    }

    private var errorTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }
}

private struct DiscordIcon: View {
    var size: CGFloat = 20
    var color: Color = .white
    var body: some View {
        DiscordShape()
            .fill(color, style: FillStyle(eoFill: true))
            .frame(width: size, height: size * 55 / 71)
    }
}

private struct DiscordShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: .init(x: w * 0.847, y: h * 0.089))
        p.addCurve(
            to: .init(x: w * 0.643, y: 0),
            control1: .init(x: w * 0.820, y: h * 0.040),
            control2: .init(x: w * 0.735, y: 0)
        )
        p.addCurve(
            to: .init(x: w * 0.570, y: h * 0.070),
            control1: .init(x: w * 0.614, y: 0),
            control2: .init(x: w * 0.587, y: h * 0.028)
        )
        p.addCurve(
            to: .init(x: w * 0.430, y: h * 0.070),
            control1: .init(x: w * 0.535, y: h * 0.098),
            control2: .init(x: w * 0.465, y: h * 0.098)
        )
        p.addCurve(
            to: .init(x: w * 0.357, y: 0),
            control1: .init(x: w * 0.413, y: h * 0.028),
            control2: .init(x: w * 0.386, y: 0)
        )
        p.addCurve(
            to: .init(x: w * 0.153, y: h * 0.089),
            control1: .init(x: w * 0.265, y: 0),
            control2: .init(x: w * 0.180, y: h * 0.040)
        )
        p.addCurve(
            to: .init(x: w * 0.004, y: h * 0.818),
            control1: .init(x: w * -0.028, y: h * 0.237),
            control2: .init(x: w * -0.043, y: h * 0.580)
        )
        p.addCurve(
            to: .init(x: w * 0.251, y: h),
            control1: .init(x: w * 0.044, y: h * 0.954),
            control2: .init(x: w * 0.141, y: h)
        )
        p.addCurve(
            to: .init(x: w * 0.307, y: h * 0.873),
            control1: .init(x: w * 0.290, y: h),
            control2: .init(x: w * 0.307, y: h * 0.929)
        )
        p.addCurve(
            to: .init(x: w * 0.693, y: h * 0.873),
            control1: .init(x: w * 0.407, y: h * 0.818),
            control2: .init(x: w * 0.593, y: h * 0.818)
        )
        p.addCurve(
            to: .init(x: w * 0.749, y: h),
            control1: .init(x: w * 0.693, y: h * 0.929),
            control2: .init(x: w * 0.710, y: h)
        )
        p.addCurve(
            to: .init(x: w, y: h * 0.818),
            control1: .init(x: w * 0.860, y: h),
            control2: .init(x: w * 0.957, y: h * 0.954)
        )
        p.addCurve(
            to: .init(x: w * 0.847, y: h * 0.089),
            control1: .init(x: w * 1.043, y: h * 0.580),
            control2: .init(x: w * 1.028, y: h * 0.237)
        )
        p.closeSubpath()
        p.addEllipse(in: .init(x: w * 0.245, y: h * 0.418, width: w * 0.178, height: h * 0.254))
        p.addEllipse(in: .init(x: w * 0.577, y: h * 0.418, width: w * 0.178, height: h * 0.254))
        return p
    }
}
