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

    // Pinch-to-zoom bookkeeping (US-12), mirroring ScanOverlayView's
    // committedScale pattern so successive pinches compose correctly
    // instead of jumping (the exact bug BUG-006 fixed there).
    @State private var committedZoomFactor: CGFloat = 1
    /// Set true while a real pinch is in progress, so a tap gesture (US-13)
    /// added on top of this same preview doesn't spuriously fire at a
    /// pinch's end location - same pattern BUG-008/009 established in
    /// ScanOverlayView.
    @State private var isInteracting = false

    var body: some View {
        ZStack {
            switch viewModel.permissionStatus {
            case .authorized:
                GeometryReader { _ in
                    CameraPreview(previewLayer: viewModel.previewLayer)
                        .contentShape(Rectangle())
                        .simultaneousGesture(magnifyGesture)
                }
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

    /// Live-camera pinch-to-zoom (US-12). Unlike ScanOverlayView's version
    /// (which zooms an already-rendered `CGImage` via `scaleEffect`/`offset`),
    /// there's no anchor/offset math needed here - `videoZoomFactor` is
    /// inherently center-fixed at the sensor level, and AVFoundation clamps
    /// it against the device's own zoom range itself. `committedZoomFactor`
    /// still needs the same read/write-at-gesture-boundary bookkeeping so
    /// successive pinches compose smoothly rather than resetting each time.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                isInteracting = true
                viewModel.setZoomFactor(committedZoomFactor * value.magnification)
            }
            .onEnded { value in
                committedZoomFactor = max(1, committedZoomFactor * value.magnification)
                scheduleInteractionReset()
            }
    }

    /// Clears `isInteracting` a beat after the gesture ends rather than
    /// synchronously, mirroring ScanOverlayView's identical `isInteracting`
    /// pattern (BUG-008/009) - avoids a race where a tap gesture resolving at
    /// the same touch-up moment could still slip through.
    private func scheduleInteractionReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isInteracting = false
        }
    }
}
