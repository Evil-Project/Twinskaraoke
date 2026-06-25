import SwiftUI

struct StorageSection: View {
    let limits: UploadLimits
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        f.countStyle = .binary
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage & Limits")
                .font(.headline)
            VStack(spacing: 14) {
                StorageMeterRow(
                    icon: "music.note",
                    label: "Songs Uploaded",
                    valueText: "\(limits.currentSongCount)/\(limits.maxSongs)",
                    ratio: ratio(limits.currentSongCount, limits.maxSongs),
                    barHeight: 4
                )
                Divider()
                StorageMeterRow(
                    icon: "internaldrive",
                    label: "Storage Used",
                    valueText: storageValueText,
                    ratio: storageRatio,
                    barHeight: 6
                )
                Divider()
                StorageMeterRow(
                    icon: "music.note.list",
                    label: "Playlists",
                    valueText: "\(limits.currentPlaylistCount)/\(limits.playlistLimit)",
                    ratio: ratio(limits.currentPlaylistCount, limits.playlistLimit),
                    barHeight: 4
                )
                Divider()
                SongsPerPlaylistRow(limit: limits.songPerPlaylistLimit)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private var storageRatio: Double {
        guard limits.maxStorageBytes > 0 else { return 0 }
        return Double(limits.usedStorageBytes) / Double(limits.maxStorageBytes)
    }

    private var storageValueText: String {
        let used = limits.usedStorageBytes == 0
            ? "0 B"
            : Self.byteFormatter.string(fromByteCount: limits.usedStorageBytes)
        let max = Self.byteFormatter.string(fromByteCount: limits.maxStorageBytes)
        return "\(used) / \(max)"
    }

    private func ratio(_ current: Int, _ max: Int) -> Double {
        guard max > 0 else { return 0 }
        return Double(current) / Double(max)
    }
}

private struct StorageMeterRow: View {
    let icon: String
    let label: String
    let valueText: String
    let ratio: Double
    let barHeight: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 28)
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(valueText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            GradientProgressBar(progress: ratio, height: barHeight)
        }
    }
}

private struct SongsPerPlaylistRow: View {
    let limit: Int
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 28)
            Text("Songs per Playlist")
                .font(.subheadline)
            Spacer()
            Text("\(limit)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
