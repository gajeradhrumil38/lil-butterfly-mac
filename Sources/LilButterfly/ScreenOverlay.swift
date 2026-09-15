import AppKit

enum ScreenEdge: String, CaseIterable {
    case left, right, top, bottom

    func restPoint(in screenFrame: CGRect, margin: CGFloat) -> CGPoint {
        let w = screenFrame.width
        let h = screenFrame.height
        switch self {
        case .left:
            return CGPoint(x: margin + CGFloat.random(in: 0...40), y: h * CGFloat.random(in: 0.2...0.8))
        case .right:
            return CGPoint(x: w - margin - CGFloat.random(in: 0...40), y: h * CGFloat.random(in: 0.2...0.8))
        case .top:
            return CGPoint(x: w * CGFloat.random(in: 0.2...0.8), y: h - margin - CGFloat.random(in: 0...30))
        case .bottom:
            return CGPoint(x: w * CGFloat.random(in: 0.2...0.8), y: margin + CGFloat.random(in: 0...30))
        }
    }

    func offscreenPoint(in screenFrame: CGRect, restX: CGFloat, restY: CGFloat, margin: CGFloat) -> CGPoint {
        let w = screenFrame.width
        let h = screenFrame.height
        switch self {
        case .left: return CGPoint(x: -40, y: restY)
        case .right: return CGPoint(x: w + 40, y: restY)
        case .top: return CGPoint(x: restX, y: h + 40)
        case .bottom: return CGPoint(x: restX, y: -40)
        }
    }
}

/// Owns one transparent overlay window covering a single NSScreen, and knows
/// how to run one full "visit": fly in from an edge, show a message, wait,
/// fly back out, and clean up.
final class ScreenOverlay {

    private let window: OverlayWindow
    private let screenFrame: CGRect
    private var isBusy = false

    init(screen: NSScreen) {
        self.window = OverlayWindow(screen: screen)
        self.screenFrame = CGRect(origin: .zero, size: screen.frame.size)
    }

    var isAvailable: Bool { !isBusy }

    func visit(message: String, pinnedAssetIndex: Int? = nil) {
        guard !isBusy, let host = window.contentView else { return }
        isBusy = true

        let edge = ScreenEdge.allCases.randomElement()!
        let margin: CGFloat = 60
        let rest = edge.restPoint(in: screenFrame, margin: margin)
        let off = edge.offscreenPoint(in: screenFrame, restX: rest.x, restY: rest.y, margin: margin)

        let butterfly = ButterflyView(center: off, pinnedAssetIndex: pinnedAssetIndex)
        host.addSubview(butterfly)

        let bubble = BubbleView(message: message)
        host.addSubview(bubble)

        func positionBubble(near point: CGPoint) {
            let onRightHalf = point.x > screenFrame.width / 2
            let x = onRightHalf
                ? point.x - butterfly.frame.width / 2 - bubble.frame.width - 10
                : point.x + butterfly.frame.width / 2 + 10
            let y = min(screenFrame.height - bubble.frame.height - 8, point.y - bubble.frame.height / 2 + 10)
            bubble.setFrameOrigin(CGPoint(x: x, y: max(8, y)))
        }
        positionBubble(near: off)

        butterfly.flyPath(from: off, to: rest, duration: 1.4, easeIn: false) { [weak self] in
            guard let self else { return }
            positionBubble(near: rest)
            bubble.fadeIn()

            let restingSeconds = 9.0
            DispatchQueue.main.asyncAfter(deadline: .now() + restingSeconds) {
                bubble.fadeOut {
                    butterfly.flyPath(from: rest, to: off, duration: 1.2, easeIn: true) {
                        butterfly.removeFromSuperview()
                        bubble.removeFromSuperview()
                        self.isBusy = false
                    }
                }
            }
        }
    }
}
