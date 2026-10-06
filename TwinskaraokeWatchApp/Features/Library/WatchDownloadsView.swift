import SwiftUI

struct WatchOutputPicker: View {
    private let bridge = WatchAuthManager.shared
    var body: some View {
        Picker("Playback Device", selection: Binding(
            get: { bridge.output }, set: { bridge.selectOutput($0) }
        )) {
            Text("iPhone").tag(CompanionPlayback.Owner.phone)
            Text("Apple Watch").tag(CompanionPlayback.Owner.watch)
        }
        .disabled(bridge.changingOutput)
        .accessibilityIdentifier("WatchPlayback.output")
        if let error = AudioManager.shared.playbackError {
            Text(error).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WatchDownloadMenu: View {
    let song: Song
    private let downloads = WatchDownloads.shared
    var body: some View {
        if let entry = downloads.entry(for: song.id) {
            switch entry.status {
            case .ready:
                Button("Remove Download", systemImage: "trash", role: .destructive) { downloads.remove(song.id) }
            case .waiting, .downloading:
                Button("Cancel Download", systemImage: "xmark") { downloads.remove(song.id) }
            case .failed:
                Button("Retry Download", systemImage: "arrow.down.circle") { downloads.download(song) }
            }
        } else {
            Button("Download to Watch", systemImage: "arrow.down.circle") { downloads.download(song) }
        }
        if let entry = downloads.entry(for: song.id) {
            if let error = entry.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            else if entry.status == .waiting { Text("Preparing download…").font(.caption) }
            else if entry.status == .downloading { ProgressView(value: entry.progress) }
        }
    }
}

struct WatchDownloadsView: View {
    private let downloads = WatchDownloads.shared
    private let bridge = WatchAuthManager.shared
    @Environment(AudioManager.self) private var audio
    @State private var showPlayer = false

    var body: some View {
        List {
            Section {
                WatchOutputPicker()
            }
            Section {
                if downloads.entries.isEmpty {
                    WatchEmptyState(systemImage: "arrow.down.circle", title: "No Downloads",
                        message: "Swipe right on a song, or open its player’s Options, then choose Download to Watch.")
                }
                ForEach(downloads.entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        if entry.status == .ready {
                            Button {
                                guard bridge.output == .watch else {
                                    audio.playbackError = "Choose Apple Watch as the playback device to play these downloads."
                                    return
                                }
                                audio.play(song: entry.song, context: downloads.songs)
                                showPlayer = true
                            } label: {
                                WatchSongRow(song: entry.song, isCurrent: audio.currentSong?.id == entry.id,
                                             isPlaying: audio.isPlaying, trailingSystemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.watchPressable)
                        } else {
                            Text(entry.song.title).font(.headline)
                            if entry.status == .failed {
                                Text(entry.error ?? "Download failed.").font(.caption).foregroundStyle(.secondary)
                                Button("Retry") { downloads.download(entry.song) }
                            } else {
                                ProgressView(value: entry.progress)
                                Text(entry.status == .waiting ? "Waiting for connection" : "Downloading…")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button("Remove", role: .destructive) { downloads.remove(entry.id) }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) { WatchDownloadMenu(song: entry.song) }
                }
            } header: {
                Text("On This Watch")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(ByteCountFormatter.string(fromByteCount: downloads.sizeBytes, countStyle: .file)) of 512 MB")
                    Text("Choose Apple Watch while your iPhone is connected. This playback device stays selected when you leave your phone. Press Play to connect AirPods or other Bluetooth headphones.")
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationDestination(isPresented: $showPlayer) { PlayerView().environment(audio) }
    }
}
