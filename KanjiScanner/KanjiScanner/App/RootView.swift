import SwiftUI

private enum Screen {
    case camera
    case processing(CGImage)
    case overlay(image: CGImage, regions: [ScanRegion])
    case results(image: CGImage, regions: [ScanRegion], result: LookupResult)
}

/// Owns the scan → overlay → results → scan-again flow (US-1 through US-7).
struct RootView: View {
    @StateObject private var cameraViewModel = CameraViewModel()
    @State private var screen: Screen = .camera

    // Owned here (not by ScanOverlayView) so it survives Results' "Back"
    // action recreating that view — resuming the same zoom/pan the user had
    // rather than resetting to the full, unzoomed photo (US-10).
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero

    private let textRecognizer = TextRecognizer()
    private let database = DictionaryDatabase.shared

    var body: some View {
        switch screen {
        case .camera:
            CameraView(viewModel: cameraViewModel) { image in
                // A genuinely new photo shouldn't inherit the previous
                // photo's zoom/pan state.
                zoomScale = 1
                zoomOffset = .zero
                screen = .processing(image)
                process(image)
            }
        case .processing:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        case let .overlay(image, regions):
            ScanOverlayView(
                image: image,
                regions: regions,
                onSelect: { result in screen = .results(image: image, regions: regions, result: result) },
                onRetake: { screen = .camera },
                scale: $zoomScale,
                offset: $zoomOffset
            )
        case let .results(image, regions, result):
            ResultsView(result: result) {
                // Back to the same captured photo, so the user can pick a
                // different detected word/kanji without re-taking the shot.
                screen = .overlay(image: image, regions: regions)
            } onScanAgain: {
                screen = .camera
            }
        }
    }

    private func process(_ image: CGImage) {
        Task {
            let regions: [ScanRegion]
            do {
                let lines = try await textRecognizer.recognizeText(in: image)
                regions = TokenBoxBuilder.buildRegions(from: lines, database: database)
            } catch {
                regions = []
            }
            screen = .overlay(image: image, regions: regions)
        }
    }
}
