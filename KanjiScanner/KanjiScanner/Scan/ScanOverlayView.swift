import SwiftUI

/// Shows the captured photo with tappable boxes over each detected kanji/word
/// region (US-2). No cropping step: tapping a box goes straight to results.
/// Supports pinch-to-zoom and drag-to-pan so small/tightly-packed text can be
/// enlarged before tapping, compensating for there being no manual crop step.
struct ScanOverlayView: View {
    let image: CGImage
    let regions: [ScanRegion]
    var onSelect: (LookupResult) -> Void
    var onRetake: () -> Void
    /// Owned by the parent (not local @State) so the current zoom/pan
    /// survives this view being torn down and recreated — e.g. when the
    /// user backs out of a result to pick a different region (US-10).
    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    private static let minZoom: CGFloat = 1
    private static let maxZoom: CGFloat = 6

    // Bookkeeping only, local to a single gesture's lifetime — re-synced
    // from the (possibly-resumed) scale/offset bindings on every appearance
    // rather than carried across view recreations itself.
    @State private var committedScale: CGFloat = minZoom
    @State private var committedOffset: CGSize = .zero
    /// True while a real pan or pinch is in progress (or just finished),
    /// used to suppress a region Button's action so starting a pan/zoom
    /// with a finger over a box doesn't also open its results (BUG-008).
    /// Deliberately doesn't touch the buttons' own hit-testing/recognition
    /// — that part already works reliably — it only gates what their
    /// action *does*. A previous attempt replaced hit-testing entirely and
    /// broke tap responsiveness for most regions (BUG-009); this is a much
    /// smaller, additive change.
    @State private var isInteracting = false

    private var imageSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    var body: some View {
        ZStack {
            if regions.isEmpty {
                lowConfidenceState
            } else {
                GeometryReader { proxy in
                    let displayRect = Self.imageDisplayRect(imageSize: imageSize, in: proxy.size)
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)

                        ForEach(regions) { region in
                            let rect = Self.viewRect(for: region.normalizedRect, in: displayRect)
                            Button(action: { selectRegion(region.result) }) {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.yellow, lineWidth: 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.yellow.opacity(0.12)))
                            }
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale, anchor: .center)
                    .offset(offset)
                    .clipped()
                    .contentShape(Rectangle())
                    // `simultaneousGesture` lets these coexist with the region
                    // buttons' own tap handling, instead of stealing touches
                    // from them.
                    .simultaneousGesture(magnifyGesture(contentSize: proxy.size))
                    .simultaneousGesture(panGesture(contentSize: proxy.size))
                }
                .ignoresSafeArea()

                retakeButton
            }
        }
        .onAppear {
            // Resume gesture bookkeeping from whatever zoom/pan the parent
            // is currently holding (e.g. carried over from before "Back"),
            // rather than always starting from an unzoomed 1x/zero state.
            committedScale = scale
            committedOffset = offset
        }
    }

    private func selectRegion(_ result: LookupResult) {
        guard !isInteracting else { return }
        onSelect(result)
    }

    /// Marks interaction active immediately, and clears it a beat after the
    /// gesture ends rather than synchronously in `onEnded` — a region
    /// Button's own action (if its lenient internal tap tolerance still let
    /// it fire despite real movement) resolves at essentially the same
    /// touch-up moment, so clearing the flag immediately risked a race where
    /// the button's action could still slip through right as the gesture
    /// finished.
    private func scheduleInteractionReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isInteracting = false
        }
    }

    /// Zooms around wherever the pinch started, by solving for the `offset`
    /// that keeps that touch point visually fixed on screen as `scale`
    /// changes — rather than moving `scaleEffect`'s anchor (which snaps the
    /// already-zoomed image to a new fixed point the instant a new pinch
    /// begins, causing a jump before any actual magnification occurs).
    /// `anchor` stays permanently `.center`; only `offset` moves.
    ///
    /// Derivation: a content point `p` renders on screen at
    /// `center + (p - center) * scale + offset`. Holding that screen
    /// position constant between the gesture's start (committedScale/
    /// committedOffset) and any point during it (newScale) and solving for
    /// the new offset gives the formula below.
    private func magnifyGesture(contentSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                isInteracting = true
                let newScale = min(max(committedScale * value.magnification, Self.minZoom), Self.maxZoom)
                let center = CGPoint(x: contentSize.width / 2, y: contentSize.height / 2)
                let touch = value.startLocation

                let rawOffset = CGSize(
                    width: committedOffset.width + (touch.x - center.x) * (committedScale - newScale),
                    height: committedOffset.height + (touch.y - center.y) * (committedScale - newScale)
                )
                offset = Self.clampedOffset(rawOffset, scale: newScale, contentSize: contentSize)
                scale = newScale
            }
            .onEnded { _ in
                committedScale = scale
                committedOffset = offset
                if scale <= Self.minZoom {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = .zero
                    }
                    committedOffset = .zero
                }
                scheduleInteractionReset()
            }
    }

    private func panGesture(contentSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                // Reaching onChanged at all means SwiftUI's own minimumDistance
                // threshold (10pt default) was crossed — a real drag, not tap
                // jitter — so this is a reliable, ready-made "is this a pan?"
                // signal without needing our own threshold math.
                isInteracting = true
                guard scale > Self.minZoom else { return }
                let rawOffset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                offset = Self.clampedOffset(rawOffset, scale: scale, contentSize: contentSize)
            }
            .onEnded { _ in
                committedOffset = offset
                scheduleInteractionReset()
            }
    }

    /// Keeps the zoomed image covering the whole viewport — without this,
    /// panning near an edge would drag the image's edge past the viewport's
    /// edge, revealing empty space behind it. At a given `scale`, the image
    /// is `contentSize * scale` wide/tall, centered on the same center as
    /// the unscaled viewport, so it extends `contentSize * (scale - 1) / 2`
    /// past each edge — that's the maximum offset in either direction.
    private static func clampedOffset(_ offset: CGSize, scale: CGFloat, contentSize: CGSize) -> CGSize {
        let maxX = max(0, contentSize.width * (scale - 1) / 2)
        let maxY = max(0, contentSize.height * (scale - 1) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private var lowConfidenceState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Couldn't confidently read this")
                .font(.title3)
                .bold()
            Text("Try retaking the photo with the text more in focus and better lit.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Retake Photo", action: onRetake)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var retakeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onRetake) {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding()
            }
            Spacer()
        }
    }

    /// Frame of the image as actually displayed under `.scaledToFit()`.
    static func imageDisplayRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let displayedHeight = containerSize.width / imageAspect
            return CGRect(x: 0, y: (containerSize.height - displayedHeight) / 2, width: containerSize.width, height: displayedHeight)
        } else {
            let displayedWidth = containerSize.height * imageAspect
            return CGRect(x: (containerSize.width - displayedWidth) / 2, y: 0, width: displayedWidth, height: containerSize.height)
        }
    }

    /// Maps a Vision-space normalized rect (origin bottom-left, y up) into
    /// SwiftUI view coordinates (origin top-left, y down) within `displayRect`.
    static func viewRect(for normalized: CGRect, in displayRect: CGRect) -> CGRect {
        let x = displayRect.minX + normalized.minX * displayRect.width
        let width = normalized.width * displayRect.width
        let topNormalized = 1 - normalized.maxY
        let y = displayRect.minY + topNormalized * displayRect.height
        let height = normalized.height * displayRect.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
