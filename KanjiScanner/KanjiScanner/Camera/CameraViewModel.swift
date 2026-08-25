import AVFoundation
import CoreGraphics
import ImageIO
import UIKit

enum CameraPermissionStatus {
    case notDetermined
    case authorized
    case denied
}

enum CameraError: Error {
    case captureFailed
    case imageConversionFailed
}

/// Owns the AVCaptureSession, camera permission state, and still-photo capture
/// (US-1). Runs the session on a dedicated background queue so SwiftUI stays
/// responsive; publishes state back to the main actor.
@MainActor
final class CameraViewModel: NSObject, ObservableObject {
    @Published private(set) var permissionStatus: CameraPermissionStatus = .notDetermined
    @Published private(set) var isSessionRunning = false

    let session = AVCaptureSession()

    /// Created once and reused for the lifetime of the view model. Recreating
    /// this on every return to the camera screen (one per SwiftUI view
    /// appearance) forced AVFoundation to renegotiate the running session's
    /// connections each time, which is slow — that was the ~5s delay on
    /// "Retake"/"Scan Again".
    let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue = DispatchQueue(label: "com.asaaugustin.KanjiScanner.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var captureContinuation: CheckedContinuation<CGImage, Error>?
    private var isConfigured = false

    /// Stored so zoom/focus/exposure calls (US-12, US-13) have a device to
    /// configure. Only ever assigned once, in `configureSession()`.
    private var device: AVCaptureDevice?

    /// Matches `ScanOverlayView.maxZoom` (US-9's captured-photo zoom) so the
    /// live viewfinder and the post-capture zoom feel consistent, rather than
    /// exposing a device's full (sometimes much larger) digital zoom range.
    private static let maxZoomFactor: CGFloat = 6

    /// Computes the correct sensor-to-interface rotation angle for this
    /// specific device/camera position — replaces manually guessing a
    /// rotation constant, which doesn't account for how the back camera's
    /// sensor is physically mounted.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer()
        super.init()
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionStatus = .authorized
            configureAndStartIfNeeded()
        case .notDetermined:
            permissionStatus = .notDetermined
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                permissionStatus = granted ? .authorized : .denied
                if granted {
                    configureAndStartIfNeeded()
                }
            }
        case .denied, .restricted:
            permissionStatus = .denied
        @unknown default:
            permissionStatus = .denied
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// Returning to the live camera after viewing results should just resume
    /// the already-configured session — no re-request of permissions (US-7).
    func resume() {
        guard permissionStatus == .authorized else { return }
        configureAndStartIfNeeded()
    }

    /// Pinch-to-zoom the live viewfinder (US-12). `factor` is the desired
    /// absolute zoom (not a delta) - the caller (a `MagnifyGesture`) is
    /// responsible for combining its own committed zoom with the gesture's
    /// relative magnification before calling this. Clamped against the
    /// device's live zoom range, not a cached copy, since this can be called
    /// at gesture-tick frequency. Fire-and-forget like `stop()` above - there's
    /// no result to hand back, the user sees the effect live via the preview.
    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [device] in
            guard let device else { return }
            let clamped = min(
                max(factor, device.minAvailableVideoZoomFactor),
                min(device.maxAvailableVideoZoomFactor, Self.maxZoomFactor)
            )
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        }
    }

    /// Tap-to-focus/expose the live viewfinder (US-13). `point` is in
    /// `previewLayer`'s own coordinate space - the conversion to the
    /// normalized device-point space `focusPointOfInterest`/
    /// `exposurePointOfInterest` expect happens here, so callers don't need
    /// to know anything about AVFoundation's coordinate system. Sets focus
    /// and exposure independently (a device could support one without the
    /// other) as a single-shot adjustment that locks once reached, mirroring
    /// system Camera.app's tap-to-focus/expose behavior - continuous
    /// autofocus/autoexposure would keep hunting, which doesn't fit a
    /// deliberate "focus here" tap on a held-steady page.
    func focus(atLayerPoint point: CGPoint) {
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        sessionQueue.async { [device] in
            guard let device else { return }
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    /// Resets zoom/focus/exposure to their defaults - called when returning
    /// to a fresh camera screen (Retake/Scan Again) so a locked focus point
    /// or non-1x zoom from the previous shot doesn't silently carry over.
    /// `device` is a persistent, never-recreated object for the life of this
    /// view model (same lifetime as `previewLayer`, see its doc comment), so
    /// nothing else resets this state automatically.
    func resetZoomAndFocus() {
        sessionQueue.async { [device] in
            guard let device else { return }
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.videoZoomFactor = 1
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }
    }

    private func configureAndStartIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            Task { @MainActor in
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: captureDevice),
           session.canAddInput(input) {
            session.addInput(input)
            device = captureDevice
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()
        isConfigured = true

        guard let device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator

        if let connection = photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(coordinator.videoRotationAngleForHorizonLevelCapture) {
            connection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        }
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(coordinator.videoRotationAngleForHorizonLevelPreview) {
            connection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        }
    }

    func capturePhoto() async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            self.captureContinuation = continuation
            let settings = AVCapturePhotoSettings()
            sessionQueue.async { [photoOutput] in
                // AVCapturePhotoOutput.capturePhoto raises an uncatchable
                // Objective-C exception (crashing the process) if there's no
                // active connection — e.g. no camera hardware present. Guard
                // it explicitly instead of letting that happen.
                guard let connection = photoOutput.connection(with: .video), connection.isActive else {
                    Task { @MainActor in
                        self.captureContinuation = nil
                        continuation.resume(throwing: CameraError.captureFailed)
                    }
                    return
                }
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            defer { captureContinuation = nil }
            if let error {
                captureContinuation?.resume(throwing: error)
                return
            }
            guard let cgImage = photo.cgImageRepresentation() else {
                captureContinuation?.resume(throwing: CameraError.imageConversionFailed)
                return
            }
            let cropped = croppedToPreviewVisibleArea(cgImage)
            let upright = normalizedToUpOrientation(cropped, metadata: photo.metadata)
            captureContinuation?.resume(returning: upright)
        }
    }

    /// AVCapturePhotoOutput captures the sensor's full field of view, which
    /// is wider than what `.resizeAspectFill` actually shows the user in the
    /// live preview. Crop the capture down to exactly the region the preview
    /// layer displayed, so OCR only ever processes what the user framed.
    ///
    /// This crop happens in the buffer's raw (sensor-native) coordinate
    /// space, matching `metadataOutputRectConverted`'s output — see
    /// `normalizedToUpOrientation` below for why that's still un-rotated.
    private func croppedToPreviewVisibleArea(_ image: CGImage) -> CGImage {
        let visibleRect = previewLayer.metadataOutputRectConverted(fromLayerRect: previewLayer.bounds)
        guard visibleRect.width > 0, visibleRect.height > 0 else { return image }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let pixelRect = CGRect(
            x: visibleRect.origin.x * width,
            y: visibleRect.origin.y * height,
            width: visibleRect.width * width,
            height: visibleRect.height * height
        ).integral

        return image.cropping(to: pixelRect) ?? image
    }

    /// `AVCapturePhoto.cgImageRepresentation()` always returns the raw,
    /// sensor-orientation pixel buffer — setting `videoRotationAngle` on the
    /// photo connection only changes the orientation *tag* written into the
    /// photo's metadata (which is what `fileDataRepresentation()`/`UIImage`
    /// would honor automatically), not the buffer `cgImageRepresentation()`
    /// hands back. So we read that tag ourselves and bake the rotation into
    /// the pixels, once, right after capture — everything downstream (Vision
    /// OCR, the on-screen overlay) can then assume the image is just upright.
    private func normalizedToUpOrientation(_ image: CGImage, metadata: [String: Any]) -> CGImage {
        guard let rawOrientation = metadata[String(kCGImagePropertyOrientation)] as? UInt32,
              let cgOrientation = CGImagePropertyOrientation(rawValue: rawOrientation) else {
            return image
        }
        let uiOrientation = Self.uiOrientation(for: cgOrientation)
        guard uiOrientation != .up else { return image }

        let oriented = UIImage(cgImage: image, scale: 1, orientation: uiOrientation)
        let renderer = UIGraphicsImageRenderer(size: oriented.size)
        let normalized = renderer.image { _ in oriented.draw(at: .zero) }
        return normalized.cgImage ?? image
    }

    private static func uiOrientation(for cgOrientation: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch cgOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        }
    }
}
