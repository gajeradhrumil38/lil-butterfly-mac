import AppKit

/// Keeps one butterfly parked near a configurable edge of the main screen.
final class DockedOverlay {
    private let window: OverlayWindow
    private let screenFrame: CGRect
    private var isBusy = false
    private var butterfly: ButterflyView?
    private var edge: ScreenEdge

    init(screen: NSScreen, edge: ScreenEdge) {
        window = OverlayWindow(screen: screen)
        screenFrame = CGRect(origin: .zero, size: screen.frame.size)
        self.edge = edge
    }

    var isAvailable: Bool { !isBusy }

    func parkNow(pinnedAssetIndex: Int?) { _ = ensureParked(pinnedAssetIndex: pinnedAssetIndex) }

    func updateEdge(_ edge: ScreenEdge) {
        self.edge = edge
        butterfly?.removeFromSuperview()
        butterfly = nil
    }

    private func dockPoint(margin: CGFloat) -> CGPoint {
        edge.restPoint(in: screenFrame, margin: margin)
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
        let bubble = BubbleView(message: message)
        host.addSubview(bubble)

        func positionBubble(near point: CGPoint) {
            let onRight = point.x > screenFrame.width / 2
            let x = onRight ? point.x - butterfly.frame.width / 2 - bubble.frame.width - 10
                            : point.x + butterfly.frame.width / 2 + 10
            let y = min(screenFrame.height - bubble.frame.height - 8,
                        point.y - bubble.frame.height / 2 + 10)
            bubble.setFrameOrigin(CGPoint(x: x, y: max(8, y)))
        }

        let restingSeconds = 9.0
        if Bool.random() {
            positionBubble(near: butterfly.layer?.position ?? dockPoint(margin: 40))
            bubble.fadeIn()
            DispatchQueue.main.asyncAfter(deadline: .now() + restingSeconds) {
                bubble.fadeOut {
                    bubble.removeFromSuperview()
                    self.isBusy = false
                }
            }
        } else {
            let dockSpot = butterfly.layer?.position ?? dockPoint(margin: 40)
            let inward = CGPoint(x: screenFrame.width * CGFloat.random(in: 0.3...0.7),
                                 y: screenFrame.height * CGFloat.random(in: 0.3...0.7))
            butterfly.flyPath(from: dockSpot, to: inward, duration: 1.2, easeIn: false) {
                positionBubble(near: inward)
                bubble.fadeIn()
                DispatchQueue.main.asyncAfter(deadline: .now() + restingSeconds) {
                    bubble.fadeOut {
                        butterfly.flyPath(from: inward, to: self.dockPoint(margin: 40), duration: 1.2, easeIn: true) {
                            bubble.removeFromSuperview()
                            self.isBusy = false
                        }
                    }
                }
            }
        }
    }
}
