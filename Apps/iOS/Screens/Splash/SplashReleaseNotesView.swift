import SwiftUI

struct SplashReleaseNotesView: View {
    let notes: SplashReleaseNotes
    let title: String?
    let version: String?
    let build: String?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.l) {
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
            Button(action: toggleExpansion) {
                Label(expanded ? LocalizedStringKey("Show less") : LocalizedStringKey("Show full changelog"),
                      systemImage: expanded ? "chevron.up" : "chevron.down")
                    .labelStyle(.titleAndIcon)
                    .padding(.vertical, AM.Spacing.m)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Splash.Changelog.Toggle")
        }
        .frame(maxWidth: 680, alignment: .leading)
        .padding(AM.Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    private func section(_ title: Text, entries: [SplashReleaseNotes.Entry]) -> some View {
        VStack(alignment: .leading, spacing: AM.Spacing.s) {
            title.font(.headline).accessibilityAddTraits(.isHeader)
            if expanded {
                ForEach(entries.enumerated(), id: \.element.id) { offset, entry in
                    VStack(alignment: .leading, spacing: AM.Spacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: AM.Spacing.s) {
                            Text("\(offset + 1).").monospacedDigit()
                            Text(entry.headline)
                        }
                        .accessibilityElement(children: .combine)
                        ForEach(entry.detailLines.enumerated(), id: \.offset) { _, line in
                            Label(line, systemImage: "minus")
                                .labelStyle(.titleAndIcon)
                                .padding(.leading, AM.Spacing.xl)
                        }
                    }
                }
            } else if let entry = entries.first {
                Label(entry.headline, systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private func toggleExpansion() {
        // The same control moves below the last note when the content changes.
        // Keep that relayout immediate so the old pressed label cannot cover the notes.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { expanded.toggle() }
    }
}
