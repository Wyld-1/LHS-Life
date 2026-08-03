//
//  MapTabView.swift
//  LHS Life
//
//  Campus map: pinch zoom, pan, double-tap zoom.
//
//  Sizing follows Apple's documented UIScrollView zoom pattern — see
//  "Basic Zooming Using the Pinch Gestures" in the Scroll View
//  Programming Guide, and the BracketStripes sample's _performSizing:
//
//    - imageView.frame and contentSize stay at the image's NATURAL size
//    - zoomScale alone does all the fitting
//    - sizing happens in layoutSubviews, not in updateUIView
//
//  The previous implementation broke all three at once:
//
//    1. It used max(w/iw, h/ih) — that's aspect FILL, which crops. Fitting
//       so the largest dimension touches the bezels is min().
//    2. It set imageView.frame to the ALREADY-SCALED size and then also set
//       zoomScale = fitScale. UIScrollView applies zoom as a transform on
//       top of the frame, so the map rendered at fitScale squared (~51pt
//       wide instead of ~393pt).
//    3. It sized in updateUIView, which is not a layout callback. At
//       makeUIView time bounds are .zero and updateUIView often runs before
//       layout, so the `bounds != lastLayoutBounds` guard failed and
//       minimumZoomScale stayed at its 0.01 placeholder — which is why the
//       map could be zoomed far out past its fitted size.
//
//  Safe-area handling: the view spans the full screen but fits and centers
//  against the gap BETWEEN the nav bar and the tab bar. Insets come from a
//  GeometryReader that deliberately stays INSIDE the safe area — see the
//  comment in body. They can't be read off the UIScrollView directly,
//  because a representable under .ignoresSafeArea() doesn't inherit
//  SwiftUI's safe area into UIView.safeAreaInsets.
//

import SwiftUI
import UIKit

// MARK: - Tuning

private enum MapTuning {
    /// How far in the user can pinch, as a multiple of the fitted scale.
    ///
    /// campus_map is 2000x1545 with only the 1x slot filled, so image.size
    /// is 2000x1545pt and the asset stays pixel-crisp only to about 1.7x
    /// fit on a 3x display. At 4x the map is upscaled ~2.4x and labels go
    /// visibly soft. Dropping a ~6000px-wide export into the 3x slot moves
    /// that ceiling to roughly 5x and changes none of the math here.
    static let maxZoomFactor: CGFloat = 4.0

    /// Where a double-tap zooms to, also a multiple of the fitted scale.
    static let doubleTapZoomFactor: CGFloat = 4.0

    /// The fitted state is the zoomed-out limit, full stop — no rubber
    /// banding below it. Flip to true for the standard springy Apple feel.
    static let allowsZoomBounce = false
}

// MARK: - Public entry point

struct MapTabView: View {

    /// Bump this to snap the map back to its fully-zoomed-out fitted state.
    /// Driven by tapping the already-selected Map tab. The Settings sheet
    /// uses the default and never resets — there's no tab there to re-tap.
    var resetToken: Int = 0

    var body: some View {
        GeometryReader { proxy in
            MapScrollViewRepresentable(
                resetToken: resetToken,
                safeInsets: proxy.safeAreaInsets
            )
            // .ignoresSafeArea() belongs HERE, on the child — not on the
            // GeometryReader. Placed on the reader, the reader itself is
            // laid out in a container whose safe area has already been
            // consumed, so proxy.safeAreaInsets reports .zero and every
            // inset calculation downstream silently adds nothing.
            //
            // Inside, the reader stays within the safe area (so it can
            // still measure it) while the scroll view expands past it, and
            // safeInsets carries real values.
            //
            // Reading them off the UIScrollView instead does NOT work:
            // a UIViewRepresentable under .ignoresSafeArea() doesn't
            // inherit SwiftUI's safe area into UIView.safeAreaInsets.
            .ignoresSafeArea()
        }
        .background(Color.lsBackground.ignoresSafeArea())
    }
}

// MARK: - Representable

private struct MapScrollViewRepresentable: UIViewRepresentable {

    let resetToken: Int
    let safeInsets: EdgeInsets

    func makeUIView(context: Context) -> CampusMapScrollView {
        let view = CampusMapScrollView()
        view.safeInsets = safeInsets.asUIEdgeInsets
        context.coordinator.lastResetToken = resetToken
        return view
    }

    func updateUIView(_ uiView: CampusMapScrollView, context: Context) {
        uiView.safeInsets = safeInsets.asUIEdgeInsets

        // Reset is edge-triggered on the token, not level-triggered on a
        // Bool — otherwise re-tapping Map twice in a row wouldn't fire the
        // second time. Same reasoning as CalendarUIState.scrollToNow.
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            uiView.resetToFit()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastResetToken = 0
    }
}

// MARK: - Scroll view

/// Its own delegate — there's no state here the Coordinator needs to own,
/// and keeping the zoom math inside the view keeps layoutSubviews and
/// scrollViewDidZoom looking at the same stored properties.
final class CampusMapScrollView: UIScrollView, UIScrollViewDelegate {

    private let imageView = UIImageView()
    private var hasSized = false
    private var lastLayoutSize: CGSize = .zero

    /// Where the nav bar and tab bar sit. Set from SwiftUI's layout pass.
    var safeInsets: UIEdgeInsets = .zero {
        didSet { if safeInsets != oldValue { setNeedsLayout() } }
    }

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)

        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        bouncesZoom = MapTuning.allowsZoomBounce
        backgroundColor = .clear

        // We compute every inset ourselves in centerContent(). Letting the
        // system also adjust for the safe area would silently change the
        // effective viewport — and therefore the fit scale — depending on
        // which NavigationStack this view happens to be inside.
        contentInsetAdjustmentBehavior = .never

        imageView.image = UIImage(named: "campus_map")
        // The frame is set to the image's exact natural size below, so
        // there's nothing to letterbox and scaleToFill avoids a redundant
        // aspect calculation inside the image view.
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("CampusMapScrollView is created in code only")
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let image = imageView.image,
              bounds.width > 0, bounds.height > 0 else { return }

        if !hasSized {
            // Natural size. NOT pre-scaled — zoomScale does the fitting.
            imageView.frame = CGRect(origin: .zero, size: image.size)
            contentSize = image.size
        }

        if !hasSized || bounds.size != lastLayoutSize {
            lastLayoutSize = bounds.size

            // Capture how far the user was zoomed in, relative to fit,
            // before the scale range moves under them.
            let previousRelativeZoom: CGFloat = (hasSized && minimumZoomScale > 0)
                ? zoomScale / minimumZoomScale
                : 1

            let fit = fittedScale(for: image.size)
            minimumZoomScale = fit
            maximumZoomScale = fit * MapTuning.maxZoomFactor

            if hasSized {
                // Bounds changed (iPad split-view resize, sheet detent).
                // Keep their relative zoom rather than snapping to fit.
                zoomScale = min(max(fit * previousRelativeZoom, fit), maximumZoomScale)
            } else {
                zoomScale = fit
                hasSized = true
            }
        }

        centerContent()
    }

    /// Aspect FIT — min(), not max(). On iPhone portrait the left/right
    /// insets are zero, so the map's width still runs bezel to bezel; the
    /// vertical insets only decide where the fitted strip gets centered.
    private func fittedScale(for imageSize: CGSize) -> CGFloat {
        let visible = gapSize
        guard visible.width > 0, visible.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(visible.width / imageSize.width,
                   visible.height / imageSize.height)
    }

    /// The gap between the bars — the area we fit and center against.
    ///
    /// NOT named visibleSize: UIScrollView already declares a `visibleSize`
    /// property, so that name silently becomes an override attempt and the
    /// compiler rejects it for missing `override` and for narrowing access
    /// to private.
    private var gapSize: CGSize {
        CGSize(width:  max(0, bounds.width  - safeInsets.left - safeInsets.right),
               height: max(0, bounds.height - safeInsets.top  - safeInsets.bottom))
    }

    /// Centering via contentInset, not by moving imageView.center — the
    /// zoom view's frame and contentSize are owned by UIScrollView while
    /// zooming, and writing to its center fights that.
    ///
    /// The safe-area insets are applied at EVERY zoom level, not just when
    /// the content is smaller than the gap. contentInset extends the
    /// scrollable range rather than clipping, so keeping them in means:
    ///
    ///   - scrolled to the top extreme, the map's top edge comes to rest
    ///     just below the header instead of underneath it — likewise the
    ///     bottom edge against the tab bar
    ///   - every other scroll position still runs the map under the
    ///     translucent bars as before
    ///
    /// Zeroing them when zoomed in (the previous behaviour) capped
    /// contentOffset.y at 0, which pinned the map's top edge to the top of
    /// the SCREEN — so the top of the map was unreachable at any zoom.
    ///
    /// slackX/slackY only add centering when the content is smaller than
    /// the gap; once it's larger they go to zero and the insets are purely
    /// the safe area.
    private func centerContent() {
        let visible = gapSize
        let content = imageView.frame.size

        let slackX = max(0, (visible.width  - content.width)  / 2)
        let slackY = max(0, (visible.height - content.height) / 2)

        let target = UIEdgeInsets(
            top:    safeInsets.top    + slackY,
            left:   safeInsets.left   + slackX,
            bottom: safeInsets.bottom + slackY,
            right:  safeInsets.right  + slackX
        )

        if contentInset != target { contentInset = target }
    }

    // MARK: Reset

    /// Back to the fully-zoomed-out state the map loaded in.
    func resetToFit(animated: Bool = true) {
        guard hasSized else { return }
        setZoomScale(minimumZoomScale, animated: animated)
    }

    // MARK: Double tap

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard hasSized else { return }
        HapticEngine.shared.tap()

        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let target = min(minimumZoomScale * MapTuning.doubleTapZoomFactor,
                             maximumZoomScale)
            let point = gesture.location(in: imageView)
            zoom(to: zoomRect(for: target, center: point), animated: true)
        }
    }

    /// Apple's zoomRectForScrollView:withScale:withCenter: utility
    /// (Scroll View Programming Guide, Listing 3-2) in Swift. setZoomScale
    /// always zooms around the center of the visible content, so getting a
    /// double tap to zoom around the TAP requires converting scale+point
    /// into a rect for zoomToRect:animated:.
    private func zoomRect(for scale: CGFloat, center: CGPoint) -> CGRect {
        let size = CGSize(width:  bounds.width  / scale,
                          height: bounds.height / scale)
        return CGRect(x: center.x - size.width  / 2,
                      y: center.y - size.height / 2,
                      width:  size.width,
                      height: size.height)
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }
}

// MARK: - Helpers

private extension EdgeInsets {
    /// LTR mapping — the campus map has no directional layout, so leading
    /// and trailing map straight onto left and right.
    var asUIEdgeInsets: UIEdgeInsets {
        UIEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing)
    }
}

#Preview { MapTabView() }
