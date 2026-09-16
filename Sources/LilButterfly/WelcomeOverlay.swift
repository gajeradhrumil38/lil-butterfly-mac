import AppKit

/// The very first thing a new user sees: the welcome message appears
/// centered on screen, framed by a ring of butterflies that arrive from the
/// screen's edges — a small "welcoming committee" moment, distinct from the
/// ordinary single-butterfly roaming visits that follow it. Choreography is
/// modeled on KaviiRevealOverlay's arrival/departure (border-scatter in,
/// scatter back out), but frames a real message bubble instead of spelling
/// out letters.
final class WelcomeOverlay {
    private let window: OverlayWindow
    private let screenFrame: CGRect
    private var ringButterflies: [ButterflyView] = []
    private var bubble: BubbleView?
    private var closeWindow: BubbleCloseWindow?
    private var isBusy = false
    private var didDismiss = false

    init(screen: NSScreen) {
        window = OverlayWindow(screen: screen)
        screenFrame = CGRect(origin: .zero, size: screen.frame.size)
    }

    func show(message: String, pinnedAssetIndex: Int?) {
        guard !isBusy, let host = window.contentView else { return }
        isBusy = true
        didDismiss = false

        let center = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
        let assetCount = max(1, WingAssets.names().count)

        // Built from the bubble's own (not-yet-displayed) size, so the
        // formation traces its actual rectangle rather than an arbitrary
        // circle — a frame that matches the message's own shape instead of
        // one that happens to surround it.
        let bubble = BubbleView(message: message)
        let margin: CGFloat = 34 // gap between the bubble's edge and the frame
        let borderRect = CGRect(
            x: center.x - bubble.frame.width / 2 - margin,
            y: center.y - bubble.frame.height / 2 - margin,
            width: bubble.frame.width + margin * 2,
            height: bubble.frame.height + margin * 2
        )
        let spacing: CGFloat = 34 // close enough to read as a continuous border
        let targets = perimeterPoints(of: borderRect, spacing: spacing)

        for (i, target) in targets.enumerated() {
            let edge = ScreenEdge.allCases.randomElement()!
            let edgePoint = edge.restPoint(in: screenFrame, margin: 0)
            let start = edge.offscreenPoint(in: screenFrame, restX: edgePoint.x, restY: edgePoint.y, margin: 0)

            let butterfly = ButterflyView(center: start, pinnedAssetIndex: Int.random(in: 0..<assetCount), displayWidth: 24)
            butterfly.alphaValue = 0
            host.addSubview(butterfly)
            ringButterflies.append(butterfly)

            let delay = Double(i) * 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.isBusy else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    butterfly.animator().alphaValue = 1
                }
                butterfly.flyPath(from: start, to: target, duration: 1.0, easeIn: false) {
                    guard self.isBusy else { return }
                    butterfly.startHover()
                }
            }
        }

        // The message arrives a beat after the border starts forming, so it
        // reads as "the butterflies bringing the message" rather than
        // everything popping in at the same instant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard self.isBusy else { return }
            bubble.setFrameOrigin(CGPoint(x: center.x - bubble.frame.width / 2, y: center.y - bubble.frame.height / 2))
            host.addSubview(bubble)
            self.bubble = bubble
            bubble.fadeIn()

            self.closeWindow = BubbleCloseWindow(frame: self.closeTargetFrameOnScreen(for: bubble)) {
                self.dismiss()
            }

            let holdSeconds = 9.0
            DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) {
                guard self.isBusy else { return }
                self.dismiss()
            }
        }
    }

    /// Evenly spaced points walking the perimeter of `rect`, roughly
    /// `spacing` apart, starting at the top-left corner and going clockwise.
    private func perimeterPoints(of rect: CGRect, spacing: CGFloat) -> [CGPoint] {
        let perimeter = 2 * (rect.width + rect.height)
        let count = max(8, Int((perimeter / spacing).rounded()))
        return (0..<count).map { i in
            pointOnPerimeter(of: rect, distance: (CGFloat(i) / CGFloat(count)) * perimeter)
        }
    }

    private func pointOnPerimeter(of rect: CGRect, distance: CGFloat) -> CGPoint {
        var d = distance
        if d <= rect.width { return CGPoint(x: rect.minX + d, y: rect.maxY) } // top, left→right
        d -= rect.width
        if d <= rect.height { return CGPoint(x: rect.maxX, y: rect.maxY - d) } // right, top→bottom
        d -= rect.height
        if d <= rect.width { return CGPoint(x: rect.maxX - d, y: rect.minY) } // bottom, right→left
        d -= rect.width
        return CGPoint(x: rect.minX, y: rect.minY + d) // left, bottom→top
    }

    private func closeTargetFrameOnScreen(for bubble: BubbleView) -> CGRect {
        guard let host = window.contentView else { return .zero }
        let target = bubble.closeTargetFrame
        let targetInWindow = host.convert(
            CGPoint(x: bubble.frame.minX + target.minX, y: bubble.frame.minY + target.minY),
            to: nil
        )
        let targetOnScreen = window.convertPoint(toScreen: targetInWindow)
        return CGRect(origin: targetOnScreen, size: target.size)
    }

    /// Shared by the resting timer and the close (x) button — whichever
    /// fires first wins, mirroring the pattern used by the ordinary visit
    /// overlays: the message fades, and the ring scatters back out past
    /// random screen edges the same way it arrived, just outbound.
    private func dismiss() {
        guard !didDismiss else { return }
        didDismiss = true

        closeWindow?.orderOut(nil)
        closeWindow = nil
        bubble?.fadeOut { [weak self] in
            self?.bubble?.removeFromSuperview()
            self?.bubble = nil
        }

        let departing = ringButterflies
        ringButterflies.removeAll()
        for (index, butterfly) in departing.enumerated() {
            butterfly.stopHover()
            let edge = ScreenEdge.allCases.randomElement()!
            let edgePoint = edge.restPoint(in: screenFrame, margin: 0)
            let off = edge.offscreenPoint(in: screenFrame, restX: edgePoint.x, restY: edgePoint.y, margin: 0)
            let delay = Double(index) * 0.02 + Double.random(in: 0...0.2)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                butterfly.flyPath(from: butterfly.centerPosition, to: off, duration: 0.9, easeIn: true) {
                    butterfly.removeFromSuperview()
                }
            }
        }

        // A fixed delay covering the longest possible fade/flight, rather
        // than tracking each individual completion — this overlay only ever
        // runs once per install, so exact precision isn't worth the
        // bookkeeping.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            self.isBusy = false
        }
    }
}
