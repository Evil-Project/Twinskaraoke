import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The pairing half of the TV sign-in screen: renders the current pairing code
/// and reflects `TVAuthManager.qrPhase` while a phone approves it.
struct TVQRSignInPanel: View {
    @ObservedObject var auth: TVAuthManager
    let onUsePassword: () -> Void

    private let codeSize: CGFloat = 320

    var body: some View {
        VStack(spacing: 24) {
            codeArea
                .frame(width: codeSize, height: codeSize)

            statusText

            VStack(spacing: 12) {
                if auth.qrPhase == .expired || auth.qrError != nil {
                    Button {
                        auth.startQRSignIn()
                    } label: {
                        Label("New Code", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                }

                TVTextButton(title: "Sign in with password instead", action: onUsePassword)
            }
        }
        .frame(width: 610)
        .padding(44)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .task {
            // Only mint a code if there isn't a live one already; re-entering
            // the tab shouldn't invalidate a code someone is mid-scan on.
            if auth.qrSession == nil, auth.qrPhase == .idle {
                auth.startQRSignIn()
            }
        }
        .onDisappear { auth.cancelQRSignIn() }
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
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .opacity(auth.qrPhase == .completing ? 0.35 : 1)
                    .overlay {
                        if auth.qrPhase == .completing {
                            ProgressView().controlSize(.large)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: auth.qrPhase)
            } else {
                placeholder { ProgressView().controlSize(.large) }
            }

        case .expired:
            placeholder {
                VStack(spacing: 14) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Code expired")
                        .font(.title3.bold())
                }
            }

        case .idle, .creating:
            placeholder {
                if auth.qrError == nil {
                    ProgressView().controlSize(.large)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func placeholder(@ViewBuilder content: () -> some View) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay { content() }
    }

    @ViewBuilder
    private var statusText: some View {
        if let error = auth.qrError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 10) {
                Text(headline)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                if auth.qrPhase == .waiting, let session = auth.qrSession {
                    Text(session.shortCode)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .tracking(6)
                        .foregroundStyle(Color.appAccent)
                    Text("Check this code matches the one on your phone before approving.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var headline: String {
        switch auth.qrPhase {
        case .idle, .creating:
            "Preparing your sign-in code…"
        case .waiting:
            "Scan with the Twinskaraoke app"
        case .completing:
            "Signing you in…"
        case .expired:
            "That code timed out for security. Get a new one."
        }
    }

    // MARK: - QR rendering

    private static let ciContext = CIContext(options: nil)

    /// Rendered at native module size and scaled with nearest-neighbour so the
    /// code stays crisp on a 4K panel instead of being interpolated to mush.
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
