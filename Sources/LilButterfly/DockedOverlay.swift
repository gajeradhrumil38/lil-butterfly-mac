import AppKit

/// Keeps one butterfly parked near a configurable edge of the main screen.
final class DockedOverlay {
    private let window: OverlayWindow
    private let screenFrame: CGRect
    private var isBusy = false
    private var butterfly: ButterflyView?
    private var closeWindow: BubbleCloseWindow?
    private var edge: ScreenEdge
    private var visitID = 0

    init(screen: NSScreen, edge: ScreenEdge) {
        window = OverlayWindow(screen: screen)
        screenFrame = CGRect(origin: .zero, size: screen.frame.size)
        self.edge = edge
    }

    var isAvailable: Bool { !isBusy }

    /// Stops this overlay completely before the app switches back to roaming
    /// or rebuilds it after a display change.
    func stop() {
        visitID += 1
        isBusy = false
        closeWindow?.orderOut(nil)
        closeWindow = nil
        window.contentView?.subviews.forEach { $0.removeFromSuperview() }
        butterfly?.layer?.removeAllAnimations()
        butterfly = nil
        window.orderOut(nil)
    }

    func parkNow(pinnedAssetIndex: Int?) { _ = ensureParked(pinnedAssetIndex: pinnedAssetIndex) }

    func updateEdge(_ edge: ScreenEdge) {
        self.edge = edge
        // Do not tear down an active visit. The new edge will be used the
        // next time the butterfly returns to its parked position.
        guard !isBusy else { return }
        butterfly?.removeFromSuperview()
        butterfly = nil
    }

    /// Left/right docking pins the butterfly's center exactly on the screen
    /// edge (x = 0 or x = screenFrame.width) so half of it renders past the
    /// window's own bounds and is naturally clipped — it reads as perched on
    /// the border rather than floating just inside it. Top/bottom keep the
    /// original fully-visible, margin-inset placement.
    private func dockPoint(margin: CGFloat) -> CGPoint {
        switch edge {
        case .left:
            return CGPoint(x: 0, y: screenFrame.height * CGFloat.random(in: 0.2...0.8))
        case .right:
            return CGPoint(x: screenFrame.width, y: screenFrame.height * CGFloat.random(in: 0.2...0.8))
        case .top, .bottom:
            return edge.restPoint(in: screenFrame, margin: margin)
        }
    }

    private func ensureParked(pinnedAssetIndex: Int?) -> ButterflyView? {
        if let butterfly { return butterfly }
        guard let host = window.contentView else { return nil }
        let view = ButterflyView(center: dockPoint(margin: 40), pinnedAssetIndex: pinnedAssetIndex)
        host.addSubview(view)
        butterfly = view
        return view
    }

    func visit(message: String, pinnedAssetIndex: Int?) {
        guard !isBusy, let host = window.contentView,
              let butterfly = ensureParked(pinnedAssetIndex: pinnedAssetIndex) else { return }
        isBusy = true
        visitID += 1
        let currentVisitID = visitID
        let bubble = BubbleView(message: message)
        host.addSubview(bubble)

        func closeTargetFrameOnScreen() -> CGRect {
            let target = bubble.closeTargetFrame
            let targetInWindow = host.convert(
                CGPoint(x: bubble.frame.minX + target.minX, y: bubble.frame.minY + target.minY),
                to: nil
            )
            let targetOnScreen = window.convertPoint(toScreen: targetInWindow)
            return CGRect(origin: targetOnScreen, size: target.size)
        }

        func positionBubble(near point: CGPoint) {
            let onRight = point.x > screenFrame.width / 2
            let x = onRight ? point.x - butterfly.frame.width / 2 - bubble.frame.width - 10
                            : point.x + butterfly.frame.width / 2 + 10
            let y = min(screenFrame.height - bubble.frame.height - 8,
                        point.y - bubble.frame.height / 2 + 10)
            bubble.setFrameOrigin(CGPoint(x: x, y: max(8, y)))
            bubble.pointTailTowardButterfly(onRight: onRight)

            if let closeWindow = self.closeWindow {
                closeWindow.setFrame(closeTargetFrameOnScreen(), display: true)
            }
        }
        positionBubble(near: butterfly.layer?.position ?? dockPoint(margin: 40))
        closeWindow = BubbleCloseWindow(frame: closeTargetFrameOnScreen()) { [weak bubble] in
            bubble?.dismiss()
        }

        let restingSeconds = 9.0
        if Bool.random() {
            butterfly.alphaValue = 1
            bubble.fadeIn()
            DispatchQueue.main.asyncAfter(deadline: .now() + restingSeconds) {
                guard self.visitID == currentVisitID else { return }
                bubble.fadeOut {
                    self.closeWindow?.orderOut(nil)
                    self.closeWindow = nil
                    guard self.visitID == currentVisitID else { return }
                    bubble.removeFromSuperview()
                    self.isBusy = false
                }
            }
        } else {
            let dockSpot = butterfly.layer?.position ?? dockPoint(margin: 40)
            let inward = CGPoint(x: screenFrame.width * CGFloat.random(in: 0.3...0.7),
                                 y: screenFrame.height * CGFloat.random(in: 0.3...0.7))
            butterfly.flyPath(from: dockSpot, to: inward, duration: 1.2, easeIn: false) {
                guard self.visitID == currentVisitID else { return }
                positionBubble(near: inward)
                butterfly.alphaValue = 1
                bubble.fadeIn()
                DispatchQueue.main.asyncAfter(deadline: .now() + restingSeconds) {
                    guard self.visitID == currentVisitID else { return }
                    bubble.fadeOut {
                        self.closeWindow?.orderOut(nil)
                        self.closeWindow = nil
                        guard self.visitID == currentVisitID else { return }
                        bubble.removeFromSuperview()
                    }
                    butterfly.flyPath(from: inward, to: self.dockPoint(margin: 40), duration: 1.2, easeIn: true) {
                        guard self.visitID == currentVisitID else { return }
                        self.closeWindow?.orderOut(nil)
                        self.closeWindow = nil
                        bubble.removeFromSuperview()
                        self.isBusy = false
                    }
                }
            }
        }
    }
}
