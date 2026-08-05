import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Pairing half of the Mac sign-in screen: renders the current pairing code and
/// reflects `MacAuthManager.qrPhase` while a signed-in phone approves it.
///
/// Mirrors `TVQRSignInPanel`, scaled down — a Mac window is closer than a TV
/// across the room, so the code doesn't need to be 320pt.
struct QRSignInPanel: View {
    let auth: MacAuthManager
    let onUsePassword: () -> Void

    private let codeSize: CGFloat = 200

    var body: some View {
        VStack(spacing: 16) {
            codeArea
                .frame(width: codeSize, height: codeSize)

            statusText

            VStack(spacing: 8) {
                if auth.qrPhase == .expired || auth.qrError != nil {
                    Button {
                        auth.startQRSignIn()
                    } label: {
                        Label("New Code", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.large)
                }

                Button("Sign in with password instead") {
                    // Choosing password sign-in retires the code: otherwise an
                    // already-scanned code could complete authentication behind
                    // a user who opted out of pairing.
                    auth.cancelQRSignIn()
                    onUsePassword()
                }
                .buttonStyle(.link)
            }
        }
        .padding(28)
        .task {
            // Only mint a code if there isn't a live one; re-opening the pane
            // shouldn't invalidate a code someone is mid-scan on.
            if auth.qrSession == nil, auth.qrPhase == .idle {
                auth.startQRSignIn()
            }
        }
        .onDisappear {
            // Ordinary navigation away leaves a live code alone so the phone
            // can approve it off-screen. Sessions end on their own via approval
            // or expiry, so nothing leaks by waiting.
            switch auth.qrPhase {
            case .waiting, .completing:
                break
            case .idle, .creating, .expired:
                auth.cancelQRSignIn()
            }
        }
    }

    @ViewBuilder
    private var codeArea: some View {
        switch auth.qrPhase {
        case .waiting, .completing:
            if let session = auth.qrSession, let image = Self.qrImage(for: session.payload) {
                Image(decorative: image, scale: 1, orientation: .up)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(auth.qrPhase == .completing ? 0.35 : 1)
                    .overlay {
                        if auth.qrPhase == .completing {
                            ProgressView()
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: auth.qrPhase)
            } else {
                placeholder { ProgressView() }
            }

        case .expired:
            placeholder {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Code expired").font(.headline)
                }
            }

        case .idle, .creating:
            placeholder {
                if auth.qrError == nil {
                    ProgressView()
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func placeholder(@ViewBuilder content: () -> some View) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .overlay { content() }
    }

    @ViewBuilder
    private var statusText: some View {
        if let error = auth.qrError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
        } else {
            VStack(spacing: 6) {
                Text(headline)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if auth.qrPhase == .waiting, let session = auth.qrSession {
                    Text(session.shortCode)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .foregroundStyle(Color.appAccent)
                        .textSelection(.enabled)
                    Text("Check this matches the code on your phone before approving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280)
                }
            }
        }
    }

    private var headline: String {
        switch auth.qrPhase {
        case .idle, .creating: "Preparing your sign-in code…"
        case .waiting: "Scan with the Twinskaraoke app"
        case .completing: "Signing you in…"
        case .expired: "That code timed out for security. Get a new one."
        }
    }

    // MARK: - QR rendering

    private static let ciContext = CIContext(options: nil)

    /// Rendered at native module size and scaled with nearest-neighbour so the
    /// code stays crisp on a Retina display instead of being interpolated.
    private static func qrImage(for payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scale = 12.0
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(scaled, from: scaled.extent)
    }
}
