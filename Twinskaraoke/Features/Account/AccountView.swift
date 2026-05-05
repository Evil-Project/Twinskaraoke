import SDWebImageSwiftUI
import SwiftUI

private struct ProfileResponse: Decodable {
  let profile: Profile
}

private struct Profile: Decodable {
  let displayName: String
  let avatarUrl: String?
}

struct AccountView: View {
  @StateObject private var auth = AuthManager()
  @EnvironmentObject var audioManager: AudioPlayerManager
  @State private var showLoginSheet = false
  @State private var profile: Profile?
  var body: some View {
    NavigationStack {
      List {
        profileSection
        generalSection
        if auth.isLoggedIn { signOutSection }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("Account")
      .sheet(isPresented: $showLoginSheet) {
        LoginSheet(auth: auth)
      }
      .task(id: auth.isLoggedIn) {
        if auth.isLoggedIn {
          await loadData()
          FavoritesManager.shared.reload()
        } else {
          profile = nil
          FavoritesManager.shared.clear()
        }
      }
    }
  }
  @ViewBuilder
  private var profileSection: some View {
    if auth.isLoggedIn {
      Section {
        NavigationLink {
          Text("Profile").navigationTitle("Profile")
        } label: {
          ProfileHeaderRow(
            displayName: profile?.displayName ?? auth.currentUsername ?? "",
            avatarUrl: profile?.avatarUrl ?? auth.currentAvatar
          )
        }
      }
    } else {
      Section {
        Button {
          showLoginSheet = true
        } label: {
          HStack(spacing: 14) {
            Image(systemName: "person.circle.fill")
              .font(.system(size: 60))
              .foregroundStyle(Color(.systemGray3))
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
        Text("Notifications").navigationTitle("Notifications")
      } label: {
        Label("Notifications", systemImage: "bell")
      }
      NavigationLink {
        SettingsView()
      } label: {
        Label("Settings", systemImage: "gearshape")
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
        auth.logout()
      } label: {
        HStack {
          Spacer()
          Text("Sign Out")
            .foregroundStyle(Color.appAccent)
          Spacer()
        }
      }
    }
  }
  private func loadData() async {
    guard let token = auth.authToken else { return }
    guard let url = URL(string: "https://api.neurokaraoke.com/api/badge/profile") else { return }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    guard let (data, _) = try? await URLSession.shared.data(for: req) else { return }
    profile = (try? JSONDecoder().decode(ProfileResponse.self, from: data))?.profile
  }
}

private struct ProfileHeaderRow: View {
  let displayName: String
  let avatarUrl: String?
  var body: some View {
    HStack(spacing: 16) {
      avatarView
        .frame(width: 64, height: 64)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(displayName)
          .font(.title3.weight(.semibold))
          .foregroundStyle(.primary)
      }
      Spacer()
    }
    .padding(.vertical, 8)
  }
  @ViewBuilder
  private var avatarView: some View {
    if let urlStr = avatarUrl, let url = URL(string: urlStr), !urlStr.isEmpty {
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
      LinearGradient(
        colors: [Color(hex: "7C5CFC"), Color(hex: "B47BFF")],
        startPoint: .topLeading, endPoint: .bottomTrailing)
      Text(String(displayName.prefix(1).uppercased()))
        .font(.system(size: 26, weight: .bold))
        .foregroundStyle(.white)
    }
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
  private var canSubmit: Bool {
    !username.isEmpty && !password.isEmpty && !auth.isLoading
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 28) {
          header
          credentialsCard
          if let err = auth.errorMessage, !err.isEmpty {
            errorBanner(err)
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
      .scrollDismissesKeyboard(.interactively)
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .navigationBarTitleDisplayMode(.inline)
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
  private var header: some View {
    VStack(spacing: 14) {
      appLogo
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
      VStack(spacing: 6) {
        Text("Sign in to Twinskaraoke")
          .font(.system(size: 26, weight: .bold))
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
    if let data = NSDataAsset(name: "AppLogo")?.data {
      AnimatedImage(data: data)
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color(hex: "7C5CFC"), Color(hex: "B47BFF")],
              startPoint: .topLeading, endPoint: .bottomTrailing
            )
          )
        Image(systemName: "music.mic")
          .font(.system(size: 40, weight: .semibold))
          .foregroundStyle(.white)
      }
    }
  }
  private var credentialsCard: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "person.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 22)
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
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 22)
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
          showPassword.toggle()
        } label: {
          Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
      .frame(height: 52)
    }
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
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
  }
  private var signInButton: some View {
    Button(action: signIn) {
      ZStack {
        if auth.isLoading {
          LoadingIndicator(size: 22)
        } else {
          Text("Sign In")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(
        LinearGradient(
          colors: [Color(hex: "7C5CFC"), Color(hex: "B47BFF")],
          startPoint: .leading, endPoint: .trailing
        )
      )
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .opacity(canSubmit ? 1 : 0.5)
    }
    .disabled(!canSubmit)
    .buttonStyle(.plain)
  }
  private var divider: some View {
    HStack(spacing: 12) {
      Rectangle().fill(Color(.separator)).frame(height: 0.5)
      Text("OR")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
      Rectangle().fill(Color(.separator)).frame(height: 0.5)
    }
  }
  private var discordButton: some View {
    Button {
      Task { await auth.loginWithDiscord() }
    } label: {
      HStack(spacing: 10) {
        DiscordIcon(size: 20, color: .white)
        Text("Continue with Discord")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(Color(hex: "5865F2"))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .disabled(auth.isLoading)
    .buttonStyle(.plain)
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
    p.addCurve(
      to: .init(x: w * 0.643, y: 0),
      control1: .init(x: w * 0.820, y: h * 0.040),
      control2: .init(x: w * 0.735, y: 0))
    p.addCurve(
      to: .init(x: w * 0.570, y: h * 0.070),
      control1: .init(x: w * 0.614, y: 0),
      control2: .init(x: w * 0.587, y: h * 0.028))
    p.addCurve(
      to: .init(x: w * 0.430, y: h * 0.070),
      control1: .init(x: w * 0.535, y: h * 0.098),
      control2: .init(x: w * 0.465, y: h * 0.098))
    p.addCurve(
      to: .init(x: w * 0.357, y: 0),
      control1: .init(x: w * 0.413, y: h * 0.028),
      control2: .init(x: w * 0.386, y: 0))
    p.addCurve(
      to: .init(x: w * 0.153, y: h * 0.089),
      control1: .init(x: w * 0.265, y: 0),
      control2: .init(x: w * 0.180, y: h * 0.040))
    p.addCurve(
      to: .init(x: w * 0.004, y: h * 0.818),
      control1: .init(x: w * -0.028, y: h * 0.237),
      control2: .init(x: w * -0.043, y: h * 0.580))
    p.addCurve(
      to: .init(x: w * 0.251, y: h),
      control1: .init(x: w * 0.044, y: h * 0.954),
      control2: .init(x: w * 0.141, y: h))
    p.addCurve(
      to: .init(x: w * 0.307, y: h * 0.873),
      control1: .init(x: w * 0.290, y: h),
      control2: .init(x: w * 0.307, y: h * 0.929))
    p.addCurve(
      to: .init(x: w * 0.693, y: h * 0.873),
      control1: .init(x: w * 0.407, y: h * 0.818),
      control2: .init(x: w * 0.593, y: h * 0.818))
    p.addCurve(
      to: .init(x: w * 0.749, y: h),
      control1: .init(x: w * 0.693, y: h * 0.929),
      control2: .init(x: w * 0.710, y: h))
    p.addCurve(
      to: .init(x: w, y: h * 0.818),
      control1: .init(x: w * 0.860, y: h),
      control2: .init(x: w * 0.957, y: h * 0.954))
    p.addCurve(
      to: .init(x: w * 0.847, y: h * 0.089),
      control1: .init(x: w * 1.043, y: h * 0.580),
      control2: .init(x: w * 1.028, y: h * 0.237))
    p.closeSubpath()
    p.addEllipse(in: .init(x: w * 0.245, y: h * 0.418, width: w * 0.178, height: h * 0.254))
    p.addEllipse(in: .init(x: w * 0.577, y: h * 0.418, width: w * 0.178, height: h * 0.254))
    return p
  }
}

extension Color {
  fileprivate init(hex: String) {
    let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var v: UInt64 = 0
    Scanner(string: h).scanHexInt64(&v)
    let a: UInt64
    let r: UInt64
    let g: UInt64
    let b: UInt64
    switch h.count {
    case 3: (a, r, g, b) = (255, (v >> 8) * 17, (v >> 4 & 0xF) * 17, (v & 0xF) * 17)
    case 6: (a, r, g, b) = (255, v >> 16, v >> 8 & 0xFF, v & 0xFF)
    case 8: (a, r, g, b) = (v >> 24, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF)
    default: (a, r, g, b) = (255, 0, 0, 0)
    }
    self.init(
      .sRGB, red: Double(r) / 255, green: Double(g) / 255,
      blue: Double(b) / 255, opacity: Double(a) / 255)
  }
}
