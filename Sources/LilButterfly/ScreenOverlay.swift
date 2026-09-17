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
    private var closeWindow: BubbleCloseWindow?
    private var choiceWindows: [ChoiceButtonWindow] = []

    init(screen: NSScreen) {
        self.window = OverlayWindow(screen: screen)
        self.screenFrame = CGRect(origin: .zero, size: screen.frame.size)
    }

    var isAvailable: Bool { !isBusy }

    func stop() {
        isBusy = false
        closeWindow?.orderOut(nil)
        closeWindow = nil
        choiceWindows.forEach { $0.orderOut(nil) }
        choiceWindows.removeAll()
        window.contentView?.subviews.forEach {
            $0.layer?.removeAllAnimations()
            $0.removeFromSuperview()
        }
        window.orderOut(nil)
    }

    func visit(
        message: String,
        pinnedAssetIndex: Int? = nil,
        displayWidth: CGFloat = ButterflySize.widths[ButterflySize.defaultIndex],
        restingSeconds: Double = 5.0,
        actionTitle: String? = nil,
        onTapped: (() -> Void)? = nil,
        checkIn: CheckInContent? = nil
    ) {
        guard !isBusy, let host = window.contentView else { return }
        isBusy = true

        let edge = ScreenEdge.allCases.randomElement()!
        let margin: CGFloat = 60
        let rest = edge.restPoint(in: screenFrame, margin: margin)
        let off = edge.offscreenPoint(in: screenFrame, restX: rest.x, restY: rest.y, margin: margin)

        let butterfly = ButterflyView(center: off, pinnedAssetIndex: pinnedAssetIndex, displayWidth: displayWidth)
        host.addSubview(butterfly)

        let choiceLabels: [String]
        if let actionTitle {
            choiceLabels = [actionTitle]
        } else if let checkIn {
            choiceLabels = checkIn.choices.map { $0.label }
        } else {
            choiceLabels = []
        }
        let bubble = BubbleView(message: message, choiceLabels: choiceLabels, checkInStyle: checkIn?.style)
        host.addSubview(bubble)

        func bubbleLocalRectOnScreen(_ local: CGRect) -> CGRect {
            let targetInWindow = host.convert(
                CGPoint(x: bubble.frame.minX + local.minX, y: bubble.frame.minY + local.minY),
                to: nil
            )
            let targetOnScreen = window.convertPoint(toScreen: targetInWindow)
            return CGRect(origin: targetOnScreen, size: local.size)
        }
        func closeTargetFrameOnScreen() -> CGRect { bubbleLocalRectOnScreen(bubble.closeTargetFrame) }
        // Inside the same rounded-rect card, reserved by BubbleView's own
        // layout whenever it's built with one or more choiceLabels — not a
        // separate floating pill below it.
        func choiceFrameOnScreen(_ index: Int) -> CGRect { bubbleLocalRectOnScreen(bubble.choiceFrame(at: index)) }

        func positionBubble(near point: CGPoint) {
            let onRightHalf = point.x > screenFrame.width / 2
            let x = onRightHalf
                ? point.x - butterfly.frame.width / 2 - bubble.frame.width - 10
                : point.x + butterfly.frame.width / 2 + 10
            let y = min(screenFrame.height - bubble.frame.height - 8, point.y - bubble.frame.height / 2 + 10)
            bubble.setFrameOrigin(CGPoint(x: x, y: max(8, y)))

            if let closeWindow = self.closeWindow {
                closeWindow.setFrame(closeTargetFrameOnScreen(), display: true)
            }
            for (index, window) in self.choiceWindows.enumerated() {
                window.setFrame(choiceFrameOnScreen(index), display: true)
            }
        }
        positionBubble(near: off)

        // Shared by the resting timer and the close (x) button, so clicking
        // close ends the visit the same way the timer would — the message
        // disappears, then the butterfly flies off — just early. The guard
        // means whichever fires first wins; the other becomes a no-op.
        var didLeave = false
        func leaveNow() {
            guard !didLeave else { return }
            didLeave = true
            butterfly.stopHover()
            // Fade the chips/close mark alongside the card itself, not
            // after it finishes — otherwise they sit at full opacity with
            // no card behind them for the whole fade, then pop away all at
            // once once bubble.fadeOut's completion runs.
            closeWindow?.fadeOutAndOrderOut(duration: BubbleView.fadeOutDuration)
            choiceWindows.forEach { $0.fadeOutAndOrderOut(duration: BubbleView.fadeOutDuration) }
            bubble.fadeOut {
                self.closeWindow = nil
                self.choiceWindows.removeAll()
                bubble.removeFromSuperview()
                butterfly.flyPath(from: butterfly.centerPosition, to: off, duration: 1.2, easeIn: true) {
                    butterfly.removeFromSuperview()
                    self.isBusy = false
                }
            }
        }

        butterfly.flyPath(from: off, to: rest, duration: 1.4, easeIn: false) {
            positionBubble(near: rest)
            butterfly.alphaValue = 1
            butterfly.startHover()
            bubble.fadeIn()

            // Created only once the butterfly has actually arrived and the
            // bubble is in its final on-screen spot — creating this upfront
            // (before the flight) computed its frame from the bubble's
            // still-off-screen position, which the horizontal offset math in
            // positionBubble doesn't keep off-screen (a wide bubble anchored
            // just past the edge extends back onto the visible screen even
            // though the butterfly itself hasn't arrived), so the close mark
            // showed up alone during the fly-in, well before the message did.
            // A real, visible button (only present for actionable messages,
            // like an update reminder) drawn inside the card's own reserved
            // bottom area — the same "one small window draws and handles
            // its own click" approach the close mark already uses, just
            // with a proper labeled control instead of an icon.
            if let checkIn {
                // A pick reveals its reply in place and holds a bit longer
                // before leaving, rather than leaving immediately like the
                // update button does — the reply is the whole point of a
                // check-in, so it needs time to actually be read.
                self.choiceWindows = checkIn.choices.enumerated().map { index, choice in
                    ChoiceButtonWindow(frame: choiceFrameOnScreen(index), title: choice.label, style: ChoiceButtonWindow.style(for: checkIn.style), dismissesOnClick: false, feedback: ChoiceButtonWindow.feedback(for: checkIn.style)) {
                        CheckInStore.record(style: checkIn.style.rawValue, choice: choice.label)
                        bubble.revealReply(choice.replies.randomElement() ?? choice.replies[0])
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            leaveNow()
                        }
                    }
                }
            } else if let onTapped {
                let window = ChoiceButtonWindow(
                    frame: choiceFrameOnScreen(0),
                    title: actionTitle ?? "Update",
                    style: .accentCapsule,
                    feedback: .scale
                ) {
                    leaveNow()
                    onTapped()
                }
                self.choiceWindows = [window]
            }
            self.closeWindow = BubbleCloseWindow(frame: closeTargetFrameOnScreen()) {
                leaveNow()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + restingSeconds) {
                leaveNow()
            }
        }
    }
}
