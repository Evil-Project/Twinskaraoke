import SwiftUI

struct AccountView: View {
    @StateObject private var auth = TVAuthManager()
    @State private var username = ""
    @State private var password = ""
    @State private var showSignOutConfirmation = false
    /// Phone pairing is the default; the password form stays reachable for
    /// anyone without the iOS app on hand.
    @State private var usePasswordSignIn = false
    @FocusState private var focusedField: LoginField?

    private enum LoginField: Hashable {
        case username
        case password
    }

    var body: some View {
        NavigationStack {
            Group {
                if auth.isLoggedIn {
                    signedInContent
                } else {
                    signInContent
                }
            }
            // See `LibraryView`: the tab bar labels this screen, and a tvOS nav
            // title floats over the scroll content instead of reserving space.
        }
        .task(id: auth.isLoggedIn) {
            if auth.isLoggedIn {
                await auth.refreshAccount()
            }
        }
        .alert("Sign out?", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task { await auth.signOut() }
            }
        } message: {
            Text("You’ll need to sign in again to access your account.")
        }
    }

    private var signInContent: some View {
        ScrollView {
            HStack(alignment: .center, spacing: 90) {
                VStack(alignment: .leading, spacing: 26) {
                    Image(systemName: usePasswordSignIn
                        ? "person.crop.circle.badge.checkmark"
                        : "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 104, weight: .medium))
                        .foregroundStyle(Color.appAccent)

                    Text("Your karaoke profile,\nright on Apple TV.")
                        .font(.system(size: 48, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(usePasswordSignIn
                        ? "Sign in with your Twinskaraoke username and password to see your profile, badges, and upload limits."
                        : "Open Twinskaraoke on your iPhone, go to Account → Sign in on web, and scan the code to sign in here.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 560, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if usePasswordSignIn {
                    passwordSignInPanel
                } else {
                    TVQRSignInPanel(auth: auth) {
                        usePasswordSignIn = true
                    }
                }
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 70)
        }
        .animation(.easeOut(duration: 0.25), value: usePasswordSignIn)
        .onChange(of: username) { _, _ in auth.clearAuthError() }
        .onChange(of: password) { _, _ in auth.clearAuthError() }
    }

    private var passwordSignInPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Sign In")
                .font(.largeTitle.bold())

            TextField("Username", text: $username)
                .font(.title2)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .username)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }

            SecureField("Password", text: $password)
                .font(.title2)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { signIn() }

            if let error = auth.authError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: signIn) {
                HStack(spacing: 14) {
                    if auth.isAuthenticating {
                        ProgressView()
                    } else {
                        Image(systemName: "person.fill.checkmark")
                    }
                    Text(auth.isAuthenticating ? "Signing In…" : "Sign In")
                }
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.appAccent)
            .controlSize(.large)
            .disabled(
                username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || password.isEmpty
                    || auth.isAuthenticating
            )

            TVTextButton(title: "Sign in with your phone instead") {
                usePasswordSignIn = false
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 610)
        .padding(44)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private var signedInContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 54) {
                profileHeader

                if let error = auth.profileError {
                    HStack(spacing: 20) {
                        Label(error, systemImage: "exclamationmark.icloud")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Try Again") {
                            Task { await auth.refreshAccount() }
                        }
                    }
                    .padding(28)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                }

                if let limits = auth.uploadLimits {
                    limitsSection(limits)
                }

                if !auth.badges.isEmpty {
                    badgesSection
                }

                HStack(spacing: 28) {
                    TVActionButton(
                        title: auth.isRefreshing ? "Refreshing…" : "Refresh Profile",
                        systemImage: "arrow.clockwise"
                    ) {
                        Task { await auth.refreshAccount() }
                    }
                    .disabled(auth.isRefreshing)

                    TVActionButton(
                        title: "Sign Out",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        isDestructive: true
                    ) {
                        showSignOutConfirmation = true
                    }
                }
                .focusSection()
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 52)
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 42) {
            TVRemoteImage(url: auth.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Circle().fill(Color.white.opacity(0.08))
                    Image(systemName: "person.fill")
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 190, height: 190)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(Color.appAccent.opacity(0.8), lineWidth: 5)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(auth.displayName)
                    .font(.system(size: 52, weight: .bold))
                    .lineLimit(1)

                if let username = auth.currentUsername,
                   username.caseInsensitiveCompare(auth.displayName) != .orderedSame
                {
                    Text("@\(username)")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                if let profile = auth.profile {
                    HStack(spacing: 18) {
                        if let level = profile.level {
                            Label("Level \(level)", systemImage: "sparkles")
                        }
                        if let title = profile.levelTitle, !title.isEmpty {
                            Text(title)
                        }
                        if let totalXP = profile.totalXP {
                            Text("\(totalXP.formatted()) XP")
                        }
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.appAccent)

                    if let progress = profile.levelProgress {
                        TVAccountProgressBar(progress: progress)
                            .frame(maxWidth: 760)
                        if let xp = profile.xpToNextLevel {
                            Text("\(xp.formatted()) XP to the next level")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if auth.isRefreshing {
                    ProgressView("Loading profile…")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(38)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private func limitsSection(_ limits: TVUploadLimits) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            TVSectionHeader(
                title: "Account Usage",
                subtitle: "Your upload and playlist allowances"
            )

            HStack(spacing: 28) {
                TVAccountMetric(
                    title: "Songs",
                    value: "\(limits.currentSongCount.formatted()) / \(limits.maxSongs.formatted())",
                    systemImage: "music.note"
                )
                TVAccountMetric(
                    title: "Storage",
                    value: "\(Self.bytes(limits.usedStorageBytes)) / \(Self.bytes(limits.maxStorageBytes))",
                    systemImage: "externaldrive"
                )
                TVAccountMetric(
                    title: "Playlists",
                    value: "\(limits.currentPlaylistCount.formatted()) / \(limits.playlistLimit.formatted())",
                    systemImage: "music.note.list"
                )
                TVAccountMetric(
                    title: "Songs per Playlist",
                    value: limits.songPerPlaylistLimit.formatted(),
                    systemImage: "list.number"
                )
            }
            // Keeps the row a single focus target from above and below, so
            // moving down out of it lands in the badges rather than sideways.
            .focusSection()
        }
    }

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            TVSectionHeader(
                title: "Badges",
                subtitle: "\(auth.badges.filter(\.unlocked).count) of \(auth.badges.count) unlocked"
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 32)],
                spacing: 32
            ) {
                ForEach(auth.badges) { badge in
                    TVBadgeCard(badge: badge)
                }
            }
        }
    }

    private func signIn() {
        guard !auth.isAuthenticating else { return }
        let submittedUsername = username
        let submittedPassword = password
        Task {
            await auth.login(username: submittedUsername, password: submittedPassword)
            if auth.isLoggedIn {
                password = ""
            }
        }
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

private struct TVAccountProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Color.appAccent)
                    .frame(width: geometry.size.width * max(0, min(progress, 1)))
            }
        }
        .frame(height: 12)
    }
}

/// Read-only, but deliberately focusable: a tvOS `ScrollView` scrolls only to
/// reveal the focused view, so a region with no focus stops cannot be scrolled
/// into view at all. Without this the usage cards were unreachable whenever
/// they fell below the fold.
private struct TVAccountMetric: View {
    let title: String
    let value: String
    let systemImage: String

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.appAccent)
            Text(value)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
        .padding(28)
        .background(
            Color.white.opacity(isFocused ? 0.18 : 0.07),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .scaleEffect(isFocused ? 1.04 : 1)
        .focusable()
        .focused($isFocused)
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

private struct TVBadgeCard: View {
    let badge: TVBadge

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 20) {
            TVRemoteImage(url: badge.iconURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: badge.unlocked ? "medal.fill" : "lock.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(badge.unlocked ? Color.appAccent : .secondary)
            }
            .frame(width: 82, height: 82)
            .saturation(badge.unlocked ? 1 : 0)
            .opacity(badge.unlocked ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 8) {
                Text(badge.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(badge.unlocked ? "Unlocked" : progressText)
                    .font(.subheadline)
                    .foregroundStyle(badge.unlocked ? Color.appAccent : .secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(24)
        .background(
            Color.white.opacity(isFocused ? 0.18 : 0.07),
            in: RoundedRectangle(cornerRadius: 22)
        )
        // Already focusable so the grid can be scrolled to; it just had no
        // visible focus state, so there was no way to see where the remote was.
        .scaleEffect(isFocused ? 1.04 : 1)
        .focusable()
        .focused($isFocused)
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(badge.name)
        .accessibilityValue(badge.unlocked ? "Unlocked" : progressText)
    }

    private var progressText: String {
        guard badge.conditionValue > 0 else { return "Locked" }
        return "\(badge.currentProgress.formatted()) of \(badge.conditionValue.formatted())"
    }
}
