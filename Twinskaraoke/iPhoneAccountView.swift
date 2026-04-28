import SwiftUI

private struct NKProfileResponse: Decodable {
    let profile: NKProfileInfo
}

private struct NKProfileInfo: Decodable {
    let displayName: String
    let avatarUrl: String?
    let level: Int
    let levelTitle: String
    let totalXP: Int
    let totalBadges: Int
    let unlockedBadges: Int
    let xpToNextLevel: Int
    let neuroCoin: Int
    let evilCoin: Int
    let twinsCoin: Int
}

private struct UploadLimits: Decodable {
    let maxSongs: Int
    let maxStorageBytes: Int
    let usedStorageBytes: Int
    let currentSongCount: Int
    let currentPlaylistCount: Int
    let playlistLimit: Int
}

struct iPhoneAccountView: View {
    @StateObject private var auth = AuthManager()
    @EnvironmentObject var audioManager: AudioPlayerManager
    @State private var showLoginSheet = false
    @State private var profile: NKProfileInfo?
    @State private var limits: UploadLimits?
    var body: some View {
        NavigationStack {
            List {
                accountSection
                generalSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Account")
            .sheet(isPresented: $showLoginSheet) {
                LoginSheet(auth: auth)
            }
            .task(id: auth.isLoggedIn) {
                if auth.isLoggedIn { await loadData() }
                else { profile = nil; limits = nil }
            }
        }
    }
    @ViewBuilder
    private var accountSection: some View {
        if auth.isLoggedIn {
            if let p = profile {
                Section {
                    ProfileHeaderRow(profile: p, auth: auth)
                }
                Section("Stats") {
                    IconLabelRow(icon: "star.fill", color: .yellow,
                                 label: "XP", value: "\(p.totalXP) / \(p.totalXP + p.xpToNextLevel)")
                    IconLabelRow(icon: "medal.fill", color: .orange,
                                 label: "Badges", value: "\(p.unlockedBadges) / \(p.totalBadges)")
                    IconLabelRow(icon: "circle.hexagongrid.fill", color: Color(hex: "7C5CFC"),
                                 label: "NeuroCoins", value: "\(p.neuroCoin)")
                    IconLabelRow(icon: "circle.hexagongrid.fill", color: .red,
                                 label: "EvilCoins", value: "\(p.evilCoin)")
                    IconLabelRow(icon: "rhombus.fill", color: Color(hex: "00B4D8"),
                                 label: "TwinsCoins", value: "\(p.twinsCoin)")
                }
                if let l = limits {
                    Section("Storage & Limits") {
                        IconLabelRow(icon: "music.note", color: .blue,
                                     label: "Songs", value: "\(l.currentSongCount) / \(l.maxSongs)")
                        IconLabelRow(icon: "list.bullet", color: .green,
                                     label: "Playlists", value: "\(l.currentPlaylistCount) / \(l.playlistLimit)")
                        StorageProgressRow(used: l.usedStorageBytes, max: l.maxStorageBytes)
                    }
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
        } else {
            Section {
                Button { showLoginSheet = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(Color(.systemGray3))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sign In")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Sign in to TwinsKaraoke")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(.systemGray3))
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
    private var generalSection: some View {
        Section {
            NavigationLink {
                Text("Settings").navigationTitle("Settings")
            } label: {
                IconLabelRow(icon: "gearshape.fill", color: .gray, label: "Settings", value: nil)
            }
            NavigationLink {
                Text("About").navigationTitle("About")
            } label: {
                IconLabelRow(icon: "info.circle.fill", color: .blue, label: "About", value: nil)
            }
            if auth.isLoggedIn {
                Button(role: .destructive) { auth.logout() } label: {
                    IconLabelRow(icon: "rectangle.portrait.and.arrow.right",
                                 color: .red, label: "Sign Out", value: nil)
                    .foregroundStyle(.red)
                }
            }
        }
    }

    private func loadData() async {
        guard let token = auth.authToken else { return }
        async let profileTask: NKProfileResponse? = apiGet(
            "https://api.neurokaraoke.com/api/badge/profile", token: token)
        async let limitsTask: UploadLimits? = apiGet(
            "https://api.neurokaraoke.com/api/user/upload-limits", token: token)
        let (p, l) = await (profileTask, limitsTask)
        profile = p?.profile
        limits = l
    }

    private func apiGet<T: Decodable>(_ urlStr: String, token: String) async -> T? {
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

private struct ProfileHeaderRow: View {
    let profile: NKProfileInfo
    let auth: AuthManager
    var body: some View {
        HStack(spacing: 14) {
            avatarView
                .frame(width: 60, height: 60)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text("Lv. \(profile.level)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(hex: "7C5CFC"))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(profile.levelTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
    @ViewBuilder
    private var avatarView: some View {
        let urlStr = profile.avatarUrl ?? auth.currentAvatar ?? ""
        if let url = URL(string: urlStr), !urlStr.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: initials
                }
            }
        } else {
            initials
        }
    }
    private var initials: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "7C5CFC"), Color(hex: "B47BFF")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(String(profile.displayName.prefix(1).uppercased()))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct IconLabelRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(label)
            if let value {
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StorageProgressRow: View {
    let used: Int
    let max: Int
    private var fraction: Double { max > 0 ? min(Double(used) / Double(max), 1.0) : 0 }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.purple)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Storage")
                    Spacer()
                    Text("\(formatBytes(used)) / \(formatBytes(max))")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                ProgressView(value: fraction)
                    .tint(fraction > 0.9 ? .red : Color(hex: "7C5CFC"))
            }
        }
    }

    private func formatBytes(_ b: Int) -> String {
        let gb = Double(b) / 1_000_000_000
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(b) / 1_000_000
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return "\(b) B"
    }
}

private struct LoginSheet: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @FocusState private var focus: LoginField?
    private enum LoginField { case username, password }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    HStack {
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
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let err = auth.errorMessage, !err.isEmpty {
                    Section {
                        Label(err, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Color.red.opacity(0.07))
                }
                Section {
                    Button(action: signIn) {
                        HStack {
                            Spacer()
                            Group {
                                if auth.isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Sign In")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            Spacer()
                        }
                        .frame(height: 44)
                        .background(
                            LinearGradient(colors: [Color(hex: "7C5CFC"), Color(hex: "B47BFF")],
                                           startPoint: .leading, endPoint: .trailing)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        )
                    }
                    .disabled(auth.isLoading || username.isEmpty || password.isEmpty)
                    .opacity(username.isEmpty || password.isEmpty ? 0.55 : 1)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                Section {
                    Button {
                        Task { await auth.loginWithDiscord() }
                    } label: {
                        HStack {
                            Spacer()
                            HStack(spacing: 10) {
                                DiscordIcon(size: 20, color: .white)
                                Text("Continue with Discord")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                        }
                        .frame(height: 44)
                        .background(
                            Color(hex: "5865F2")
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        )
                    }
                    .disabled(auth.isLoading)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("TwinsKaraoke")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: auth.isLoggedIn) { _, isLoggedIn in
                if isLoggedIn { dismiss() }
            }
        }
    }

    private func signIn() {
        focus = nil
        Task { await auth.login(username: username, password: password) }
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
        p.addCurve(to: .init(x: w * 0.643, y: 0),
                   control1: .init(x: w * 0.820, y: h * 0.040),
                   control2: .init(x: w * 0.735, y: 0))
        p.addCurve(to: .init(x: w * 0.570, y: h * 0.070),
                   control1: .init(x: w * 0.614, y: 0),
                   control2: .init(x: w * 0.587, y: h * 0.028))
        p.addCurve(to: .init(x: w * 0.430, y: h * 0.070),
                   control1: .init(x: w * 0.535, y: h * 0.098),
                   control2: .init(x: w * 0.465, y: h * 0.098))
        p.addCurve(to: .init(x: w * 0.357, y: 0),
                   control1: .init(x: w * 0.413, y: h * 0.028),
                   control2: .init(x: w * 0.386, y: 0))
        p.addCurve(to: .init(x: w * 0.153, y: h * 0.089),
                   control1: .init(x: w * 0.265, y: 0),
                   control2: .init(x: w * 0.180, y: h * 0.040))
        p.addCurve(to: .init(x: w * 0.004, y: h * 0.818),
                   control1: .init(x: w * -0.028, y: h * 0.237),
                   control2: .init(x: w * -0.043, y: h * 0.580))
        p.addCurve(to: .init(x: w * 0.251, y: h),
                   control1: .init(x: w * 0.044, y: h * 0.954),
                   control2: .init(x: w * 0.141, y: h))
        p.addCurve(to: .init(x: w * 0.307, y: h * 0.873),
                   control1: .init(x: w * 0.290, y: h),
                   control2: .init(x: w * 0.307, y: h * 0.929))
        p.addCurve(to: .init(x: w * 0.693, y: h * 0.873),
                   control1: .init(x: w * 0.407, y: h * 0.818),
                   control2: .init(x: w * 0.593, y: h * 0.818))
        p.addCurve(to: .init(x: w * 0.749, y: h),
                   control1: .init(x: w * 0.693, y: h * 0.929),
                   control2: .init(x: w * 0.710, y: h))
        p.addCurve(to: .init(x: w, y: h * 0.818),
                   control1: .init(x: w * 0.860, y: h),
                   control2: .init(x: w * 0.957, y: h * 0.954))
        p.addCurve(to: .init(x: w * 0.847, y: h * 0.089),
                   control1: .init(x: w * 1.043, y: h * 0.580),
                   control2: .init(x: w * 1.028, y: h * 0.237))
        p.closeSubpath()
        p.addEllipse(in: .init(x: w * 0.245, y: h * 0.418, width: w * 0.178, height: h * 0.254))
        p.addEllipse(in: .init(x: w * 0.577, y: h * 0.418, width: w * 0.178, height: h * 0.254))
        return p
    }
}

fileprivate extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:  (a,r,g,b) = (255,(v>>8)*17,(v>>4&0xF)*17,(v&0xF)*17)
        case 6:  (a,r,g,b) = (255,v>>16,v>>8&0xFF,v&0xFF)
        case 8:  (a,r,g,b) = (v>>24,v>>16&0xFF,v>>8&0xFF,v&0xFF)
        default: (a,r,g,b) = (255,0,0,0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
}
