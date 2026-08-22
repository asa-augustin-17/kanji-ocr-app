import SwiftUI
import AVFoundation

/// Hosts CameraViewModel's single, persistent AVCaptureVideoPreviewLayer
/// inside SwiftUI. Re-parents that same layer into whatever container view
/// exists each time this appears, instead of creating a fresh preview layer
/// per appearance — the latter forced AVFoundation to renegotiate the
/// already-running session's connections on every "Retake"/"Scan Again",
/// which is what caused the several-second delay.
private struct CameraPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> ContainerView {
        let view = ContainerView()
        view.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        uiView.previewLayer = previewLayer
    }

    final class ContainerView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                guard previewLayer !== oldValue, let previewLayer else { return }
                layer.addSublayer(previewLayer)
                setNeedsLayout()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}

/// The app's home screen: a live camera viewfinder with a single capture
/// control (US-1, FR-1, FR-2). Opens directly — no landing page, no login.
struct CameraView: View {
    @ObservedObject var viewModel: CameraViewModel
    var onCapture: (CGImage) -> Void

    @State private var isCapturing = false
    @State private var captureError: String?

    var body: some View {
        ZStack {
            switch viewModel.permissionStatus {
            case .authorized:
                CameraPreview(previewLayer: viewModel.previewLayer)
                    .ignoresSafeArea()
                captureControls
            case .denied:
                PermissionDeniedView()
            case .notDetermined:
                Color.black.ignoresSafeArea()
            }
        }
        .onAppear { viewModel.start() }
        .alert("Couldn't capture photo", isPresented: .constant(captureError != nil), actions: {
            Button("OK") { captureError = nil }
        }, message: {
            Text(captureError ?? "")
        })
    }

    private var captureControls: some View {
        VStack {
            Spacer()
            Button(action: capture) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 2))
            }
            .disabled(isCapturing)
            .padding(.bottom, 40)
            .accessibilityLabel("Capture photo")
        }
    }

    private func capture() {
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let image = try await viewModel.capturePhoto()
                onCapture(image)
            } catch {
                captureError = error.localizedDescription
            }
        }
    }
}
