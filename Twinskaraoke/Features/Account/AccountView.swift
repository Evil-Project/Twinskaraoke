import SwiftUI

struct AccountView: View {
    @State private var auth = AuthManager()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showLoginSheet = false
    @State private var showQRApprove = false
    @State private var showSignOutConfirm = false
    @State private var profile: Profile?
    @State private var badges: [Badge] = []
    @State private var uploadLimits: UploadLimits?
    @State private var levelUpAnnouncement: LevelUpAnnouncement?

    private var usesWideOverview: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            accountContent
                .navigationTitle("Account")
                .navigationBarTitleDisplayMode(.large)
                .sheet(isPresented: $showLoginSheet) {
                    LoginSheet(auth: auth)
                }
                .sheet(isPresented: $showQRApprove) {
                    QRApproveView(auth: auth)
                }
                .sheet(item: $levelUpAnnouncement) { announcement in
                    LevelUpSheet(announcement: announcement)
                        .presentationDetents([.medium])
                        .presentationBackground(.clear)
                }
                .task(id: auth.isLoggedIn) {
                    if auth.isLoggedIn {
                        await loadData()
                        FavoritesManager.shared.reload()
                    } else {
                        profile = nil
                        badges = []
                        uploadLimits = nil
                        levelUpAnnouncement = nil
                        FavoritesManager.shared.clear()
                    }
                }
        }
    }

    @ViewBuilder
    private var accountContent: some View {
        if usesWideOverview {
            ZStack(alignment: .top) {
                ScreenBackgroundFill(style: .grouped)
                accountList
                    .frame(maxWidth: 640, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, AM.Spacing.screenMargin)
                    .accessibilityIdentifier("Account.WideOverview")
            }
        } else {
            accountList
        }
    }

    private var accountList: some View {
        List {
            profileSection
            generalSection
            if auth.isLoggedIn { signOutSection }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .groupedScreenBackground()
        .refreshable {
            if auth.isLoggedIn {
                AppHaptic.selection.play()
                await loadData()
            }
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        if auth.isLoggedIn {
            Section {
                NavigationLink {
                    ProfileDetailView(
                        displayName: profile?.displayName ?? auth.currentUsername ?? "",
                        avatarUrl: profile?.avatarUrl ?? auth.currentAvatar,
                        profile: profile,
                        badges: badges,
                        uploadLimits: uploadLimits
                    )
                } label: {
                    ProfileHeaderRow(
                        displayName: profile?.displayName ?? auth.currentUsername ?? "",
                        avatarUrl: profile?.avatarUrl ?? auth.currentAvatar,
                        level: profile?.level,
                        levelTitle: profile?.levelTitle,
                        levelProgress: profile?.levelProgress,
                        xpToNextLevel: profile?.xpToNextLevel
                    )
                }
                if !unlockedBadges.isEmpty {
                    UnlockedBadgesRow(
                        badges: unlockedBadges,
                        unlockedCount: profile?.unlockedBadges ?? unlockedBadges.count,
                        totalCount: profile?.totalBadges ?? badges.count
                    )
                }
            }
        } else {
            Section {
                Button {
                    AppHaptic.selection.play()
                    showLoginSheet = true
                } label: {
                    SignInPromptRow()
                }
                .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82))
                .accessibilityLabel("Sign In")
                .accessibilityHint("Opens account sign-in.")
            }
        }
    }

    private var generalSection: some View {
        Section {
            if auth.isLoggedIn {
                Button {
                    AppHaptic.selection.play()
                    showQRApprove = true
                } label: {
                    Label("Sign in on web", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(PressableButtonStyle(scale: 0.98, dim: 0.82))
                .accessibilityLabel("Sign in on web")
                .accessibilityHint("Shows a QR code to authorize a browser session.")
            }
            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            NavigationLink {
                NotificationsView()
            } label: {
                Label("Notifications", systemImage: "bell")
            }
            NavigationLink {
                AboutView()
            } label: {
                Label("About", systemImage: "info.circle")
            }
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                AppHaptic.warning.play()
                showSignOutConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("Sign Out")
                        .foregroundStyle(Color.appAccent)
                    Spacer()
                }
            }
            .alert("Sign out?", isPresented: $showSignOutConfirm) {
                Button("Cancel", role: .cancel) {}
                    .tint(Color(uiColor: .systemBlue))
                Button("Sign Out", role: .destructive) {
                    AppHaptic.warning.play()
                    auth.logout()
                }
            } message: {
                Text("You'll need to sign in again to access your library and account features.")
            }
            .accessibilityLabel("Sign Out")
            .accessibilityHint("Asks for confirmation before signing out.")
        }
    }

    private var unlockedBadges: [Badge] {
        badges.filter(\.unlocked)
    }

    private func loadData() async {
        guard let token = auth.authToken else { return }
        async let badgeData = fetchAuthorized(path: "/api/badge/profile", token: token)
        async let limitData = fetchAuthorized(path: "/api/user/upload-limits", token: token)
        if let data = await badgeData,
           let decoded = try? JSONDecoder().decode(ProfileResponse.self, from: data)
        {
            handleLevelChange(with: decoded.profile)
            profile = decoded.profile
            badges = decoded.badges ?? []
            persistAvatarIfNeeded(decoded.profile.avatarUrl)
        }
        if let data = await limitData,
           let decoded = try? JSONDecoder().decode(UploadLimits.self, from: data)
        {
            uploadLimits = decoded
        }
    }

    /// The toolbar avatar reads "nk.avatar"; keep it in sync with the server
    /// profile so accounts whose login token carried no avatar still get one.
    private func persistAvatarIfNeeded(_ avatarUrl: String?) {
        guard let avatarUrl, !avatarUrl.isEmpty else { return }
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "nk.avatar") != avatarUrl {
            defaults.set(avatarUrl, forKey: "nk.avatar")
        }
    }

    private func fetchAuthorized(path: String, token: String) async -> Data? {
        guard let url = URL(string: "\(StorageHost.api)\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try? await URLSession.shared.data(for: req).0
    }

    private func handleLevelChange(with newProfile: Profile) {
        guard let level = newProfile.level, level > 0 else { return }
        guard let identity = auth.currentUserId ?? auth.currentUsername, !identity.isEmpty else {
            return
        }

        let key = "nk.lastSeenLevel.\(identity)"
        let defaults = UserDefaults.standard

        if defaults.object(forKey: key) == nil {
            defaults.set(level, forKey: key)
            return
        }

        let previousLevel = defaults.integer(forKey: key)
        if level > previousLevel {
            levelUpAnnouncement = LevelUpAnnouncement(
                previousLevel: previousLevel,
                currentLevel: level,
                levelTitle: newProfile.levelTitle
            )
        }
        defaults.set(level, forKey: key)
    }
}

private struct SignInPromptRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.fill")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text("Sign In")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Sign in to access your library")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(AM.Font.chevron)
                .foregroundStyle(.tertiary)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sign In")
        .accessibilityHint("Sign in to access your library.")
    }
}
