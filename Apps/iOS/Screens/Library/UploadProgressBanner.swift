import SwiftUI

/// One row per upload in `SongUploadController`, at the top of the Uploaded
/// list: where it is, and the action that fits. A finished upload's row goes
/// away by itself once its song is in the list; a failed one stays until the
/// user retries or dismisses it.
struct UploadProgressBanner: View {
    let controller: SongUploadController

    /// How long a finished upload's row stays on screen.
    private static let finishedRowLifetime: Duration = .seconds(6)

    var body: some View {
        ForEach(controller.uploads) { item in
            UploadProgressRow(
                item: item,
                cancel: {
                    AppHaptic.dismiss.play()
                    controller.cancel(item.id)
                },
                retry: {
                    AppHaptic.commit.play()
                    controller.retry(item.id)
                },
                dismiss: {
                    AppHaptic.dismiss.play()
                    controller.dismiss(item.id)
                }
            )
            .task(id: item.phase) {
                guard case .succeeded = item.phase else { return }
                try? await Task.sleep(for: Self.finishedRowLifetime)
                guard !Task.isCancelled else { return }
                controller.dismiss(item.id)
            }
        }
    }
}

private struct UploadProgressRow: View {
    let item: SongUploadItem
    let cancel: () -> Void
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AM.Spacing.s) {
            status
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "\(title), \(phaseText)"))
                .accessibilityValue(percentText ?? "")
                .accessibilityActions { actionButtons }
                .accessibilityIdentifier("Uploads.Progress.Status")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AM.Spacing.s) { actionButtons }
                VStack(alignment: .leading, spacing: AM.Spacing.s) { actionButtons }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(.vertical, AM.Spacing.s)
    }

    private var status: some View {
        HStack(alignment: .top, spacing: AM.Spacing.m) {
            icon
            VStack(alignment: .leading, spacing: AM.Spacing.xs) {
                Text(verbatim: title)
                    .font(AM.Font.rowTitle)
                    .lineLimit(2)
                Text(phaseText)
                    .font(AM.Font.rowSubtitle)
                    .foregroundStyle(isFailed ? Color.appDestructive : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case let .uploading(fraction) = item.phase {
                    ProgressView(value: fraction)
                        .tint(.appAccent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.phase {
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.appAccent)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.appDestructive)
        default:
            ProgressView()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch item.phase {
        case let .failed(failure):
            if failure.isRetryable {
                Button("Retry", action: retry)
                    .accessibilityIdentifier("Uploads.Progress.Retry")
            }
            Button("Dismiss", action: dismiss)
                .accessibilityIdentifier("Uploads.Progress.Dismiss")
        case .succeeded, .finishing:
            EmptyView()
        default:
            Button("Cancel", action: cancel)
                .accessibilityIdentifier("Uploads.Progress.Cancel")
        }
    }

    private var isFailed: Bool {
        if case .failed = item.phase { true } else { false }
    }

    /// The server's title once a link import has one, else what the user gave.
    private var title: String {
        if case let .succeeded(serverTitle) = item.phase, !serverTitle.isEmpty { return serverTitle }
        return item.title.isEmpty ? String(localized: "Untitled Song") : item.title
    }

    private var phaseText: String {
        switch item.phase {
        case .waiting: String(localized: "Waiting…")
        case .checkingQuota: String(localized: "Checking storage…")
        case .preparing: String(localized: "Preparing…")
        case .uploading: String(localized: "Uploading…")
        case .finishing: String(localized: "Finishing…")
        case .importing: String(localized: "Importing. This can take a few minutes.")
        case .succeeded: String(localized: "Added to your uploads.")
        case let .failed(failure): failure.userMessage
        }
    }

    private var percentText: String? {
        guard case let .uploading(fraction) = item.phase else { return nil }
        return String(localized: "\(Int((fraction * 100).rounded())) percent")
    }
}

/// Plays and announces the end of an upload once, wherever it is first
/// seen on the Uploaded screen, then clears it from the controller.
struct UploadCompletionFeedback: ViewModifier {
    let controller: SongUploadController

    func body(content: Content) -> some View {
        content.onChange(of: controller.latestCompletion, initial: true) { oldValue, completion in
            guard let completion else { return }
            // The initial call reports an upload that ended while the user
            // was elsewhere: announced, but no haptic for something past.
            if oldValue != completion {
                (completion.succeeded ? AppHaptic.success : AppHaptic.error).play()
            }
            AccessibilityNotification.Announcement(Self.message(for: completion)).post()
            controller.acknowledgeCompletion()
        }
    }

    static func message(for completion: SongUploadCompletion) -> String {
        switch (completion.succeeded, completion.title.isEmpty) {
        case (true, false): String(localized: "Added “\(completion.title)” to your uploads.")
        case (true, true): String(localized: "Your upload finished.")
        case (false, false): String(localized: "“\(completion.title)” couldn't be uploaded.")
        case (false, true): String(localized: "An upload failed.")
        }
    }
}
