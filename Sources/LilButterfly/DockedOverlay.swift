import AppKit

/// Keeps one butterfly parked near a configurable edge of the main screen.
/// The parked butterfly itself is clickable (dismiss it until the next
/// scheduled visit re-parks it) and draggable along its edge (the chosen
/// spot is persisted via onPositionChanged).
final class DockedOverlay {
    private let window: OverlayWindow
    private let screenFrame: CGRect
    private var isBusy = false
    private var butterfly: ButterflyView?
    private var closeWindow: BubbleCloseWindow?
    private var choiceWindows: [ChoiceButtonWindow] = []
    private var handleWindow: DockedButterflyHandleWindow?
    private var edge: ScreenEdge
    private var positionFraction: Double?
    private var dragStartCenter: CGPoint?
    private var visitID = 0

    /// Called after a drag ends with the new fraction (0...1) along the
    /// edge, so the caller can persist it.
    var onPositionChanged: ((Double) -> Void)?

    init(screen: NSScreen, edge: ScreenEdge, positionFraction: Double?) {
        window = OverlayWindow(screen: screen)
        screenFrame = CGRect(origin: .zero, size: screen.frame.size)
        self.edge = edge
        self.positionFraction = positionFraction
    }

    var isAvailable: Bool { !isBusy }

    /// Stops this overlay completely before the app switches back to roaming
    /// or rebuilds it after a display change.
    func stop() {
        removeButterflyAndVisit()
        window.orderOut(nil)
    }

    func parkNow(pinnedAssetIndex: Int?, displayWidth: CGFloat) { _ = ensureParked(pinnedAssetIndex: pinnedAssetIndex, displayWidth: displayWidth) }

    func updateEdge(_ edge: ScreenEdge, positionFraction: Double?) {
        self.edge = edge
        self.positionFraction = positionFraction
        // Do not tear down an active visit. The new edge will be used the
        // next time the butterfly returns to its parked position.
        guard !isBusy else { return }
        butterfly?.removeFromSuperview()
        butterfly = nil
        handleWindow?.orderOut(nil)
        handleWindow = nil
    }

    /// Left/right docking pins the butterfly's center exactly on the screen
    /// edge (x = 0 or x = screenFrame.width) so half of it renders past the
    /// window's own bounds and is naturally clipped — it reads as perched on
    /// the border rather than floating just inside it. Top/bottom keep the
    /// original fully-visible, margin-inset placement. When the user has
    /// dragged the butterfly to a specific spot, that fraction wins over the
    /// usual random placement along the edge.
    private func dockPoint(margin: CGFloat) -> CGPoint {
        switch edge {
        case .left, .right:
            let y = positionFraction.map { CGFloat($0) * screenFrame.height }
                ?? (screenFrame.height * CGFloat.random(in: 0.2...0.8))
            return CGPoint(x: edge == .left ? 0 : screenFrame.width, y: clamp(y, 20, screenFrame.height - 20))
        case .top, .bottom:
            guard let positionFraction else {
                return edge.restPoint(in: screenFrame, margin: margin)
            }
            // Reuse restPoint for the normal-axis (toward/away from the
            // edge) coordinate, but override the along-edge coordinate with
            // the user's chosen spot.
            let base = edge.restPoint(in: screenFrame, margin: margin)
            let x = clamp(CGFloat(positionFraction) * screenFrame.width, 20, screenFrame.width - 20)
            return CGPoint(x: x, y: base.y)
        }
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private func ensureParked(pinnedAssetIndex: Int?, displayWidth: CGFloat) -> ButterflyView? {
        if let butterfly { return butterfly }
        guard let host = window.contentView else { return nil }
        let view = ButterflyView(center: dockPoint(margin: 40), pinnedAssetIndex: pinnedAssetIndex, displayWidth: displayWidth)
        host.addSubview(view)
        butterfly = view
        attachHandleWindow()
        return view
    }

    // MARK: - Click to dismiss, drag to reposition

    private func attachHandleWindow() {
        handleWindow?.orderOut(nil)
        let frame = visibleButterflyFrameOnScreen()
        guard !frame.isEmpty else { return }
        handleWindow = DockedButterflyHandleWindow(
            frame: frame,
            onDrag: { [weak self] dx, dy in self?.handleDrag(dx: dx, dy: dy) },
            onDragEnd: { [weak self] in self?.handleDragEnd() },
            onClick: { [weak self] in self?.handleClick() }
        )
    }

    private func updateHandleWindowFrame() {
        guard let handleWindow else { return }
        let frame = visibleButterflyFrameOnScreen()
        guard !frame.isEmpty else { return }
        handleWindow.setFrame(frame, display: true)
    }

    /// The handle window should only cover the portion of the butterfly that
    /// is actually on screen (half of it renders off-window when docked to
    /// a left/right edge), so clicks land on visible pixels.
    private func visibleButterflyFrameOnScreen() -> CGRect {
        guard let butterfly, let host = window.contentView else { return .zero }
        let visibleInWindow = butterfly.frame.intersection(CGRect(origin: .zero, size: screenFrame.size))
        guard !visibleInWindow.isNull, !visibleInWindow.isEmpty else { return .zero }
        let originInWindow = host.convert(visibleInWindow.origin, to: nil)
        let originOnScreen = window.convertPoint(toScreen: originInWindow)
        return CGRect(origin: originOnScreen, size: visibleInWindow.size)
    }

    private func handleDrag(dx: CGFloat, dy: CGFloat) {
        guard let butterfly else { return }
        if dragStartCenter == nil {
            dragStartCenter = butterfly.centerPosition
        }
        guard let start = dragStartCenter else { return }
        var newPosition = start
        switch edge {
        case .left, .right:
            newPosition.y = clamp(start.y + dy, 20, screenFrame.height - 20)
        case .top, .bottom:
            newPosition.x = clamp(start.x + dx, 20, screenFrame.width - 20)
        }
        butterfly.layer?.removeAllAnimations()
        butterfly.centerPosition = newPosition
        updateHandleWindowFrame()
    }

    private func handleDragEnd() {
        defer { dragStartCenter = nil }
        guard let butterfly else { return }
        let center = butterfly.centerPosition
        let fraction: Double
        switch edge {
        case .left, .right:
            fraction = Double(center.y / screenFrame.height)
        case .top, .bottom:
            fraction = Double(center.x / screenFrame.width)
        }
        positionFraction = fraction
        onPositionChanged?(fraction)
    }

    private func handleClick() {
        removeButterflyAndVisit()
    }

    private func removeButterflyAndVisit() {
        visitID += 1
        isBusy = false
        closeWindow?.orderOut(nil)
        closeWindow = nil
        choiceWindows.forEach { $0.orderOut(nil) }
        choiceWindows.removeAll()
        window.contentView?.subviews.forEach { $0.removeFromSuperview() }
        butterfly?.layer?.removeAllAnimations()
        butterfly = nil
        handleWindow?.orderOut(nil)
        handleWindow = nil
    }

    func visit(message: String, pinnedAssetIndex: Int?, displayWidth: CGFloat, restingSeconds: Double, actionTitle: String? = nil, onTapped: (() -> Void)? = nil, checkIn: CheckInContent? = nil) {
        guard !isBusy, let host = window.contentView,
              let butterfly = ensureParked(pinnedAssetIndex: pinnedAssetIndex, displayWidth: displayWidth) else { return }
        isBusy = true
        visitID += 1
        let currentVisitID = visitID
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
        func choiceFrameOnScreen(_ index: Int) -> CGRect { bubbleLocalRectOnScreen(bubble.choiceFrame(at: index)) }

        func positionBubble(near point: CGPoint) {
            let onRight = point.x > screenFrame.width / 2
            let x = onRight ? point.x - butterfly.frame.width / 2 - bubble.frame.width - 10
                            : point.x + butterfly.frame.width / 2 + 10
            let y = min(screenFrame.height - bubble.frame.height - 8,
                        point.y - bubble.frame.height / 2 + 10)
            bubble.setFrameOrigin(CGPoint(x: x, y: max(8, y)))

            if let closeWindow = self.closeWindow {
                closeWindow.setFrame(closeTargetFrameOnScreen(), display: true)
            }
            for (index, window) in self.choiceWindows.enumerated() {
                window.setFrame(choiceFrameOnScreen(index), display: true)
            }
            self.updateHandleWindowFrame()
        }
        positionBubble(near: butterfly.centerPosition)

        // leaveNow is reassigned below once we know which variant is
        // running (it differs in whether the butterfly flies anywhere
        // afterward); the close button always calls whatever leaveNow
        // currently is — ending the visit the same way the resting timer
        // would, just early: the message fades, then (if applicable) the
        // butterfly departs. The window itself is created per-branch, only
        // once the bubble's final position is known and it's about to
        // become visible — creating it upfront (before venture-and-settle's
        // flight to `inward`) computed its frame from the original dock
        // spot, so the close mark showed up alone there while the message
        // was still invisible and the butterfly was off flying elsewhere.
        var didLeave = false
        var leaveNow: () -> Void = {}

        if Bool.random() {
            butterfly.alphaValue = 1
            butterfly.startHover()
            bubble.fadeIn()
            if let checkIn {
                choiceWindows = checkIn.choices.enumerated().map { index, choice in
                    ChoiceButtonWindow(frame: choiceFrameOnScreen(index), title: choice.label, style: ChoiceButtonWindow.style(for: checkIn.style), dismissesOnClick: false, feedback: ChoiceButtonWindow.feedback(for: checkIn.style)) {
                        CheckInStore.record(style: checkIn.style.rawValue, choice: choice.label)
                        bubble.revealReply(choice.replies.randomElement() ?? choice.replies[0])
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            leaveNow()
                        }
                    }
                }
            } else if let onTapped {
                let window = ChoiceButtonWindow(frame: choiceFrameOnScreen(0), title: actionTitle ?? "Update", style: .accentCapsule, feedback: .scale) {
                    leaveNow()
                    onTapped()
                }
                choiceWindows = [window]
            }
            closeWindow = BubbleCloseWindow(frame: closeTargetFrameOnScreen()) {
                leaveNow()
            }

            leaveNow = {
                guard !didLeave, self.visitID == currentVisitID else { return }
                didLeave = true
                butterfly.stopHover()
                bubble.fadeOut {
                    self.closeWindow?.orderOut(nil)
                    self.closeWindow = nil
                    self.choiceWindows.forEach { $0.orderOut(nil) }
                    self.choiceWindows.removeAll()
                    guard self.visitID == currentVisitID else { return }
                    bubble.removeFromSuperview()
                    self.isBusy = false
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + restingSeconds) {
                leaveNow()
            }
        } else {
            let dockSpot = butterfly.centerPosition
            let inward = CGPoint(x: screenFrame.width * CGFloat.random(in: 0.3...0.7),
                                 y: screenFrame.height * CGFloat.random(in: 0.3...0.7))
            butterfly.flyPath(from: dockSpot, to: inward, duration: 1.2, easeIn: false) {
                guard self.visitID == currentVisitID else { return }
                positionBubble(near: inward)
                butterfly.alphaValue = 1
                butterfly.startHover()
                bubble.fadeIn()
                if let checkIn {
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
                    let window = ChoiceButtonWindow(frame: choiceFrameOnScreen(0), title: actionTitle ?? "Update", style: .accentCapsule, feedback: .scale) {
                        leaveNow()
                        onTapped()
                    }
                    self.choiceWindows = [window]
                }
                self.closeWindow = BubbleCloseWindow(frame: closeTargetFrameOnScreen()) {
                    leaveNow()
                }

                leaveNow = {
                    guard !didLeave, self.visitID == currentVisitID else { return }
                    didLeave = true
                    butterfly.stopHover()
                    bubble.fadeOut {
                        self.closeWindow?.orderOut(nil)
                        self.closeWindow = nil
                        self.choiceWindows.forEach { $0.orderOut(nil) }
                        self.choiceWindows.removeAll()
                        guard self.visitID == currentVisitID else { return }
                        bubble.removeFromSuperview()
                        butterfly.flyPath(from: butterfly.centerPosition, to: self.dockPoint(margin: 40), duration: 1.2, easeIn: true) {
                            guard self.visitID == currentVisitID else { return }
                            self.isBusy = false
                            self.updateHandleWindowFrame()
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + restingSeconds) {
                    leaveNow()
                }
            }
        }
    }
}
