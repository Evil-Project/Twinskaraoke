import SwiftUI

struct AccountView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @State private var showsFullGuestID = false

    private var reduceMotion: Bool {
        AppMotion.reduceMotion(
            systemReduceMotion: systemReduceMotion,
            respectPreference: respectReducedMotion
        )
    }

    var body: some View {
        List {
            Section {
                WatchAccountHeader()
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section("Session") {
                Button {
                    showsFullGuestID.toggle()
                    WatchHaptic.play(showsFullGuestID ? .success : .click)
                } label: {
                    WatchAccountTokenRow(
                        title: "Guest ID",
                        value: guestIDText,
                        showsFullValue: showsFullGuestID
                    )
                }
                .buttonStyle(.watchPressable)
                .accessibilityLabel("Guest ID")
                .accessibilityValue(showsFullGuestID ? GuestIdentity.current : guestIDText)
                .accessibilityHint(showsFullGuestID ? "Hides the full guest ID." : "Reveals the full guest ID.")

                WatchAccountStatusRow(
                    systemImage: "antenna.radiowaves.left.and.right",
                    tint: .appAccent,
                    title: "Service",
                    value: serviceRegionText
                )
            }

            Section("Playback") {
                WatchAccountStatusRow(
                    systemImage: "applewatch",
                    tint: .blue,
                    title: "On This Watch Only",
                    value: "The watch app plays on its own; it does not sync with the iPhone app"
                )
                WatchAccountStatusRow(
                    systemImage: "checkmark.seal.fill",
                    tint: .green,
                    title: "Guest playback",
                    value: "Ready for browsing and music"
                )
            }

            Section("Motion") {
                Toggle("Respect Reduce Motion", isOn: $respectReducedMotion)
                    .compatibleOnChange(of: respectReducedMotion) { _ in
                        WatchHaptic.play(.click)
                    }
            }
        }
        .navigationTitle("Account")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showsFullGuestID)
    }

    private var guestIDText: String {
        if showsFullGuestID {
            return GuestIdentity.current
        }
        return "\(GuestIdentity.current.prefix(8))..."
    }

    private var serviceRegionText: String {
        StorageHost.api.contains(".cn") ? "China CDN" : "Global CDN"
    }
}

private struct WatchAccountHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(Color.appAccent.opacity(0.15))
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundColor(.appAccent)
                }
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Guest Listener")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("Not signed in")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                WatchAccountPill(systemImage: "music.note", title: "Browse")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Guest Listener")
        .accessibilityValue("Not signed in")
    }
}

private struct WatchAccountPill: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundColor(.appAccent)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appAccent.opacity(0.12))
            )
    }
}

private struct WatchAccountTokenRow: View {
    let title: String
    let value: String
    let showsFullValue: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: showsFullValue ? "eye.fill" : "number")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.appAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.appAccent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            Spacer(minLength: 4)

            Image(systemName: showsFullValue ? "eye.slash" : "eye")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

private struct WatchAccountStatusRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint.opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
