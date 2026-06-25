import AVFoundation
import SwiftUI

struct QRApproveView: View {
    @ObservedObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var phase: Phase = .scanning
    @State private var permission: CameraPermission = .unknown

    enum Phase {
        case scanning
        case confirming(sessionId: String)
        case approving(sessionId: String)
        case success
        case failure(String)
    }

    enum CameraPermission {
        case unknown
        case granted
        case denied
        case unavailable(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                content
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Sign in on web")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        AppHaptic.light.play()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.appGlassForeground)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task { await checkPermission() }
        .animation(phaseAnimation, value: phaseKey)
        .animation(permissionAnimation, value: permissionKey)
    }

    private var content: some View {
        Group {
            switch phase {
            case .scanning:
                scanner
            case let .confirming(sid):
                confirmCard(sessionId: sid)
            case .approving:
                statusCard(
                    icon: "hourglass",
                    tint: .appAccent,
                    title: "Approving...",
                    subtitle: "Keep this screen open while the web session is confirmed."
                )
            case .success:
                statusCard(
                    icon: "checkmark.circle.fill",
                    tint: .green,
                    title: "Signed in on web",
                    subtitle: "You can return to your browser."
                )
            case let .failure(msg):
                statusCard(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: "Couldn't sign in",
                    subtitle: msg,
                    retry: true
                )
            }
        }
        .id(phaseKey)
        .transition(contentTransition)
    }

    @ViewBuilder
    private var scanner: some View {
        switch permission {
        case .unknown:
            QRPermissionLoadingView()
        case .denied:
            QRPermissionDeniedView {
                AppHaptic.selection.play()
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        case let .unavailable(message):
            QRCameraUnavailableView(
                message: message,
                retry: retryCameraCheck,
                dismiss: {
                    AppHaptic.light.play()
                    dismiss()
                }
            )
        case .granted:
            ZStack {
                QRCameraView(onScan: handleScan, onFailure: handleCameraFailure)
                    .ignoresSafeArea()
                QRScannerChrome()
                    .ignoresSafeArea()
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                VStack {
                    Spacer()
                    QRScannerInstructionPanel()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 34)
                }
            }
        }
    }

    private var phaseKey: String {
        switch phase {
        case .scanning:
            "scanning"
        case .confirming:
            "confirming"
        case .approving:
            "approving"
        case .success:
            "success"
        case .failure:
            "failure"
        }
    }

    private var permissionKey: String {
        switch permission {
        case .unknown: "unknown"
        case .granted: "granted"
        case .denied: "denied"
        case .unavailable: "unavailable"
        }
    }

    private func confirmCard(sessionId: String) -> some View {
        VStack(spacing: 22) {
            QRHeroGlyph(systemImage: "lock.shield.fill", tint: .appAccent)

            VStack(spacing: 8) {
                Text("Sign in on web?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text(
                    "Approving signs in \(auth.currentUsername ?? "your account") on the device showing this QR code."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                QRInfoRow(
                    symbol: "person.crop.circle",
                    title: "Account",
                    value: auth.currentUsername ?? "Current user"
                )
                Divider().padding(.leading, 40)
                QRInfoRow(
                    symbol: "display",
                    title: "Web session",
                    value: String(sessionId.prefix(8)).uppercased()
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.appControlInactiveFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 10) {
                Button {
                    AppHaptic.medium.play()
                    Task { await approve(sessionId: sessionId) }
                } label: {
                    QRActionLabel(title: "Approve", systemImage: "checkmark.circle.fill", isPrimary: true)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))

                Button {
                    AppHaptic.light.play()
                    withOptionalAnimation(phaseAnimation) {
                        phase = .scanning
                    }
                } label: {
                    QRActionLabel(title: "Cancel", systemImage: "xmark.circle", isPrimary: false)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
            }
        }
        .padding(24)
        .frame(maxWidth: 390)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.appDivider, lineWidth: 1)
        )
        .shadow(color: Color.appShadow, radius: 24, y: 12)
        .padding(.horizontal, 22)
    }

    private func statusCard(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String?,
        retry: Bool = false
    ) -> some View {
        VStack(spacing: 20) {
            QRHeroGlyph(systemImage: icon, tint: tint, isSpinning: icon == "hourglass")

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                if retry {
                    AppHaptic.selection.play()
                    withOptionalAnimation(phaseAnimation) {
                        phase = .scanning
                    }
                } else {
                    AppHaptic.light.play()
                    dismiss()
                }
            } label: {
                QRActionLabel(
                    title: retry ? "Try Again" : "Done",
                    systemImage: retry ? "arrow.clockwise" : "checkmark",
                    isPrimary: true
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
        }
        .padding(24)
        .frame(maxWidth: 390)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.appDivider, lineWidth: 1)
        )
        .shadow(color: Color.appShadow, radius: 24, y: 12)
        .padding(.horizontal, 22)
    }

    private func handleScan(_ value: String) {
        guard case .scanning = phase else { return }
        guard let sessionId = parseSessionId(from: value) else { return }
        AppHaptic.success.play()
        withOptionalAnimation(phaseAnimation) {
            phase = .confirming(sessionId: sessionId)
        }
    }

    private func handleCameraFailure(_ message: String) {
        guard case .scanning = phase else { return }
        AppHaptic.error.play()
        withOptionalAnimation(permissionAnimation) {
            permission = .unavailable(message)
        }
    }

    private func parseSessionId(from raw: String) -> String? {
        if let url = URL(string: raw),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = comps.queryItems?.first(where: { $0.name == "sessionId" })?.value,
           !id.isEmpty
        {
            return id
        }
        if let comps = URLComponents(string: "?\(raw)"),
           let id = comps.queryItems?.first(where: { $0.name == "sessionId" })?.value,
           !id.isEmpty
        {
            return id
        }
        return nil
    }

    private func approve(sessionId: String) async {
        withOptionalAnimation(phaseAnimation) {
            phase = .approving(sessionId: sessionId)
        }
        do {
            try await auth.approveQRSession(sessionId: sessionId)
            AppHaptic.success.play()
            withOptionalAnimation(phaseAnimation) {
                phase = .success
            }
        } catch let AuthManager.AuthError.http(code, _) {
            let msg = switch code {
            case 404: "This QR code expired. Refresh it and try again."
            case 401: "Your session expired. Sign in again."
            default: "Server error (\(code))."
            }
            AppHaptic.error.play()
            withOptionalAnimation(phaseAnimation) {
                phase = .failure(msg)
            }
        } catch {
            AppHaptic.error.play()
            withOptionalAnimation(phaseAnimation) {
                phase = .failure(error.localizedDescription)
            }
        }
    }

    private func retryCameraCheck() {
        AppHaptic.selection.play()
        withOptionalAnimation(permissionAnimation) {
            permission = .unknown
        }
        Task { await checkPermission() }
    }

    @MainActor
    private func checkPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = Self.hasVideoCaptureDevice ? .granted : .unavailable(Self.cameraUnavailableMessage)
        case .notDetermined:
            guard Self.hasVideoCaptureDevice else {
                permission = .unavailable(Self.cameraUnavailableMessage)
                return
            }
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permission = granted
                ? (Self.hasVideoCaptureDevice ? .granted : .unavailable(Self.cameraUnavailableMessage))
                : .denied
        case .denied, .restricted:
            permission = .denied
        @unknown default:
            permission = .denied
        }
    }

    private static var hasVideoCaptureDevice: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil ||
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil ||
            AVCaptureDevice.default(for: .video) != nil
    }

    private static let cameraUnavailableMessage =
        "This device can't open the camera right now. Check that the camera is working, then try again."

    private var contentTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97)).combined(with: .move(edge: .bottom)),
                removal: .opacity.combined(with: .scale(scale: 1.02))
            )
    }

    private var phaseAnimation: Animation? {
        reduceMotion ? nil : AppMotion.spring(response: 0.36, dampingFraction: 0.84)
    }

    private var permissionAnimation: Animation? {
        reduceMotion ? nil : AppMotion.spring(response: 0.2, dampingFraction: 0.9)
    }
}

private struct QRPermissionLoadingView: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            QRHeroGlyph(systemImage: "camera.viewfinder", tint: .appAccent, isPulsing: pulse)
            VStack(spacing: 6) {
                Text("Checking Camera Access")
                    .font(.title3.weight(.bold))
                Text("The scanner will open as soon as access is ready.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            ProgressView()
                .controlSize(.regular)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.appDivider, lineWidth: 1)
        )
        .shadow(color: Color.appShadow, radius: 22, y: 10)
        .padding(.horizontal, 24)
        .onAppear {
            withOptionalAnimation(pulseAnimation) {
                pulse = true
            }
        }
    }

    private var pulseAnimation: Animation? {
        reduceMotion ? nil : AppMotion.spring(response: 1.15, dampingFraction: 0.82).repeatForever(autoreverses: true)
    }
}

private struct QRPermissionDeniedView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            QRHeroGlyph(systemImage: "video.slash", tint: Color.secondary)
            VStack(spacing: 8) {
                Text("Camera Access Is Off")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Enable camera access in Settings to scan a sign-in code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: openSettings) {
                QRActionLabel(title: "Open Settings", systemImage: "gearshape.fill", isPrimary: true)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
        }
        .padding(24)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.appDivider, lineWidth: 1)
        )
        .shadow(color: Color.appShadow, radius: 22, y: 10)
        .padding(.horizontal, 24)
    }
}

private struct QRCameraUnavailableView: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            QRHeroGlyph(systemImage: "camera.badge.ellipsis", tint: Color.secondary)
            VStack(spacing: 8) {
                Text("Camera Unavailable")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                Button(action: retry) {
                    QRActionLabel(title: "Try Again", systemImage: "arrow.clockwise", isPrimary: true)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))

                Button(action: dismiss) {
                    QRActionLabel(title: "Done", systemImage: "checkmark", isPrimary: false)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96, dim: 0.78))
            }
        }
        .padding(24)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.appDivider, lineWidth: 1)
        )
        .shadow(color: Color.appShadow, radius: 22, y: 10)
        .padding(.horizontal, 24)
    }
}

private struct QRScannerChrome: View {
    private let frameScale: CGFloat = 0.76
    private let frameCornerRadius: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * frameScale
            ZStack {
                QRScannerDimMask(cutoutSide: side, cornerRadius: frameCornerRadius)
                    .fill(Color.black.opacity(0.36), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                RoundedRectangle(cornerRadius: frameCornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .frame(width: side, height: side)
                    .overlay(QRCornerBrackets(cornerRadius: frameCornerRadius))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct QRScannerDimMask: Shape {
    let cutoutSide: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cutoutRect = CGRect(
            x: rect.midX - cutoutSide / 2,
            y: rect.midY - cutoutSide / 2,
            width: cutoutSide,
            height: cutoutSide
        )

        path.addRect(rect)
        path.addRoundedRect(
            in: cutoutRect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}

private struct QRCornerBrackets: View {
    let cornerRadius: CGFloat
    private let lineWidth: CGFloat = 5

    var body: some View {
        QRCornerBracketShape(cornerRadius: cornerRadius, lineWidth: lineWidth)
            .stroke(
                Color.white,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
    }
}

private struct QRCornerBracketShape: Shape {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let drawingRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let side = min(drawingRect.width, drawingRect.height)
        let length = side * 0.18
        let radius = min(length * 0.42, max(lineWidth, cornerRadius - lineWidth * 1.5))
        var path = Path()

        path.move(to: CGPoint(x: drawingRect.minX, y: drawingRect.minY + length))
        path.addLine(to: CGPoint(x: drawingRect.minX, y: drawingRect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: drawingRect.minX + radius, y: drawingRect.minY),
            control: CGPoint(x: drawingRect.minX, y: drawingRect.minY)
        )
        path.addLine(to: CGPoint(x: drawingRect.minX + length, y: drawingRect.minY))

        path.move(to: CGPoint(x: drawingRect.maxX - length, y: drawingRect.minY))
        path.addLine(to: CGPoint(x: drawingRect.maxX - radius, y: drawingRect.minY))
        path.addQuadCurve(
            to: CGPoint(x: drawingRect.maxX, y: drawingRect.minY + radius),
            control: CGPoint(x: drawingRect.maxX, y: drawingRect.minY)
        )
        path.addLine(to: CGPoint(x: drawingRect.maxX, y: drawingRect.minY + length))

        path.move(to: CGPoint(x: drawingRect.minX, y: drawingRect.maxY - length))
        path.addLine(to: CGPoint(x: drawingRect.minX, y: drawingRect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: drawingRect.minX + radius, y: drawingRect.maxY),
            control: CGPoint(x: drawingRect.minX, y: drawingRect.maxY)
        )
        path.addLine(to: CGPoint(x: drawingRect.minX + length, y: drawingRect.maxY))

        path.move(to: CGPoint(x: drawingRect.maxX - length, y: drawingRect.maxY))
        path.addLine(to: CGPoint(x: drawingRect.maxX - radius, y: drawingRect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: drawingRect.maxX, y: drawingRect.maxY - radius),
            control: CGPoint(x: drawingRect.maxX, y: drawingRect.maxY)
        )
        path.addLine(to: CGPoint(x: drawingRect.maxX, y: drawingRect.maxY - length))

        return path
    }
}

private struct QRScannerInstructionPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Scan Web Sign-In Code")
                    .font(.headline)
            } icon: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.headline)
                    .foregroundStyle(Color.appAccent)
            }
            Text("Point the camera at the QR code shown on twinskaraoke.com.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("You will approve the session before signing in.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }
}

private struct QRHeroGlyph: View {
    let systemImage: String
    let tint: Color
    var isSpinning = false
    var isPulsing = false
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.largeTitle.bold())
            .foregroundStyle(tint)
            .frame(width: 86, height: 86)
            .background(tint.opacity(0.12), in: Circle())
            .overlay(Circle().stroke(tint.opacity(0.22), lineWidth: 1))
            .scaleEffect(isPulsing && animate ? 1.06 : 1)
            .rotationEffect(.degrees(isSpinning && animate ? 360 : 0))
            .shadow(color: tint.opacity(0.18), radius: 16, y: 8)
            .animation(heroAnimation, value: animate)
            .onAppear {
                animate = !reduceMotion && (isSpinning || isPulsing)
            }
    }

    private var heroAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return isSpinning
            ? AppMotion.spring(response: 1.3, dampingFraction: 0.9).repeatForever(autoreverses: false)
            : AppMotion.spring(response: 1.05, dampingFraction: 0.82).repeatForever(autoreverses: true)
    }
}

private struct QRInfoRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Color.appAccent)
                .frame(width: 44, height: 44)
                .background(Color.appAccent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

private struct QRActionLabel: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(isPrimary ? Color.appControlActiveForeground : Color.appAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                isPrimary ? Color.appControlActiveFill : Color.appControlInactiveFill,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

private struct QRCameraView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> QRCameraController {
        let vc = QRCameraController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_: QRCameraController, context _: Context) {}

    final class Coordinator: NSObject, QRCameraControllerDelegate {
        let onScan: (String) -> Void
        let onFailure: (String) -> Void
        init(onScan: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onFailure = onFailure
        }

        func qrCameraController(_: QRCameraController, didScan value: String) {
            onScan(value)
        }

        func qrCameraController(_: QRCameraController, didFail message: String) {
            onFailure(message)
        }
    }
}

private protocol QRCameraControllerDelegate: AnyObject {
    func qrCameraController(_ controller: QRCameraController, didScan value: String)
    func qrCameraController(_ controller: QRCameraController, didFail message: String)
}

private final class QRCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: QRCameraControllerDelegate?
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "org.evilneuro.Twinskaraoke.qr-camera-session", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var runtimeErrorObserver: NSObjectProtocol?
    private var hasReported = false
    private var isSessionConfigured = false
    private var hasReportedFailure = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        observeRuntimeErrors()
        configureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    deinit {
        if let runtimeErrorObserver {
            NotificationCenter.default.removeObserver(runtimeErrorObserver)
        }
        stopSession()
    }

    private func stopSession() {
        let capturedSession = session
        sessionQueue.async {
            guard capturedSession.isRunning else { return }
            capturedSession.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    private func configureSession() {
        guard let device = Self.preferredVideoDevice else {
            reportFailure("This device doesn't have an available camera for scanning QR codes.")
            return
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            reportFailure("The camera couldn't be opened. Check that it isn't blocked by another app, then try again.")
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input) else {
            reportFailure("The camera couldn't be prepared for scanning.")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            reportFailure("The QR scanner couldn't start on this device.")
            return
        }
        session.addOutput(output)

        guard output.availableMetadataObjectTypes.contains(.qr) else {
            reportFailure("This camera doesn't support QR code scanning.")
            return
        }

        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
        isSessionConfigured = true
    }

    private func startSession() {
        guard isSessionConfigured else { return }
        let capturedSession = session
        sessionQueue.async {
            guard !capturedSession.isRunning else { return }
            capturedSession.startRunning()
        }
    }

    private func observeRuntimeErrors() {
        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.reportFailure("The camera stopped unexpectedly. Check that it is working, then try again.")
        }
    }

    private func reportFailure(_ message: String) {
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            delegate?.qrCameraController(self, didFail: message)
        }
    }

    private static var preferredVideoDevice: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ??
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ??
            AVCaptureDevice.default(for: .video)
    }

    func metadataOutput(
        _: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from _: AVCaptureConnection
    ) {
        guard !hasReported,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr,
              let value = obj.stringValue
        else { return }
        hasReported = true
        delegate?.qrCameraController(self, didScan: value)
    }
}
