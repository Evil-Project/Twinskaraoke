import SwiftUI

struct SplashReleaseNotesView: View {
    let notes: SplashReleaseNotes
    let title: String?
    let version: String?
    let build: String?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title, !title.isEmpty {
                Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            } else {
                Text("What’s new").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            }
            if let build { Text("Build \(build)").font(.subheadline) }
            if !notes.watchOS.isEmpty {
                section(Text("watchOS \(notes.watchVersion)"), entries: notes.watchOS)
            }
            if !notes.iOS.isEmpty, let version {
                section(Text("iOS \(version)"), entries: notes.iOS)
            }
            if !notes.general.isEmpty {
                section(Text("General"), entries: notes.general)
            }
            Button {
                expanded.toggle()
            } label: {
                Text(expanded ? LocalizedStringKey("Show less") : LocalizedStringKey("Show full changelog"))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("Splash.Changelog.Toggle")
        }
        .frame(maxWidth: 680, alignment: .leading)
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private func section(_ title: Text, entries: [SplashReleaseNotes.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title.font(.headline).accessibilityAddTraits(.isHeader)
            if expanded {
                ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(offset + 1).").monospacedDigit()
                            Text(entry.headline)
                        }
                        .accessibilityElement(children: .combine)
                        ForEach(Array(entry.detailLines.enumerated()), id: \.offset) { _, line in
                            Label(line, systemImage: "minus")
                                .labelStyle(.titleAndIcon)
                                .padding(.leading, 20)
                        }
                    }
                }
            } else if let entry = entries.first {
                Label(entry.headline, systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}
