@preconcurrency import AVFoundation
import Observation
import SwiftUI
import UI
import UIKit

struct PairingQRCodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme
    @State private var scanner = PairingQRCodeScanner()

    let onPayloadScanned: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DevysSpacing.space3) {
                Text("Scan the pairing QR code shown by mac-server.")
                    .font(DevysTypography.sm)
                    .foregroundStyle(theme.textSecondary)

                scannerContent

                Text("If scanning is unavailable, paste the payload text manually in the Pair step.")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(DevysSpacing.space4)
            .background(theme.base)
            .navigationTitle("Pairing QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            scanner.onPayloadScanned = { payload in
                onPayloadScanned(payload)
                dismiss()
            }
            scanner.start()
        }
        .onDisappear {
            scanner.stop()
        }
    }

    @ViewBuilder
    private var scannerContent: some View {
        switch scanner.state {
        case .running:
            PairingQRCodeScannerPreview(session: scanner.captureSession)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                        .stroke(theme.borderSubtle, lineWidth: 1)
                )

        case .requestingPermission:
            scannerMessageCard("Requesting camera permission…")

        case .denied:
            VStack(alignment: .leading, spacing: DevysSpacing.space2) {
                scannerMessageCard("Camera access is disabled. Enable camera access for Devys in iOS Settings.")

                Button("Open Settings") {
                    openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }

        case .noCamera:
            scannerMessageCard("No camera is available on this device.")

        case .failed(let message):
            scannerMessageCard(message)

        case .idle:
            scannerMessageCard("Preparing scanner…")
        }
    }

    private func scannerMessageCard(_ message: String) -> some View {
        Text(message)
            .font(DevysTypography.xs)
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .padding(DevysSpacing.space3)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .stroke(theme.borderSubtle, lineWidth: 1)
            )
    }

    private func openSystemSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }
}

@Observable
final class PairingQRCodeScanner: NSObject, @unchecked Sendable {
    enum State: Equatable {
        case idle
        case requestingPermission
        case running
        case denied
        case noCamera
        case failed(String)
    }

    private(set) var state: State = .idle

    let captureSession = AVCaptureSession()
    var onPayloadScanned: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "devys.ios.pairing.scanner.session")
    private var didConfigureSession = false
    private var hasDeliveredPayload = false

    func start() {
        hasDeliveredPayload = false

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRunSessionIfNeeded()

        case .notDetermined:
            transition(to: .requestingPermission)
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted {
                        self.configureAndRunSessionIfNeeded()
                    } else {
                        self.transition(to: .denied)
                    }
                }
            }

        case .denied, .restricted:
            transition(to: .denied)

        @unknown default:
            transition(to: .failed("Camera authorization state is unsupported."))
        }
    }

    func stop() {
        sessionQueue.async { [captureSession] in
            guard captureSession.isRunning else { return }
            captureSession.stopRunning()
        }
    }

    private func configureAndRunSessionIfNeeded() {
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            transition(to: .noCamera)
            return
        }

        if !didConfigureSession {
            do {
                try configureSession(videoDevice)
                didConfigureSession = true
            } catch {
                transition(to: .failed("Unable to configure QR scanner camera session."))
                return
            }
        }

        transition(to: .running)
        sessionQueue.async { [captureSession] in
            guard !captureSession.isRunning else { return }
            captureSession.startRunning()
        }
    }

    private func configureSession(_ videoDevice: AVCaptureDevice) throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .high

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard captureSession.canAddInput(videoInput) else {
            throw PairingQRCodeScannerError.unableToAddInput
        }
        captureSession.addInput(videoInput)

        let output = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(output) else {
            throw PairingQRCodeScannerError.unableToAddOutput
        }
        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
    }

    private func transition(to nextState: State) {
        state = nextState
    }
}

extension PairingQRCodeScanner: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasDeliveredPayload else { return }

        let readableCodes = metadataObjects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
        guard let payload = readableCodes.first(where: { $0.type == .qr })?.stringValue,
              !payload.isEmpty else {
            return
        }

        hasDeliveredPayload = true
        stop()
        onPayloadScanned?(payload)
    }
}

private enum PairingQRCodeScannerError: Error {
    case unableToAddInput
    case unableToAddOutput
}

private struct PairingQRCodeScannerPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PairingQRCodeScannerPreviewView {
        let view = PairingQRCodeScannerPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PairingQRCodeScannerPreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class PairingQRCodeScannerPreviewView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer backing layer.")
        }
        return layer
    }
}
