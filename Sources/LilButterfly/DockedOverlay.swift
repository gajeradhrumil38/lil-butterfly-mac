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
    // NSPanel rather than ChoiceButtonWindow: the energy slider's single
    // continuous drag surface is an EnergySliderWindow, not a row of
    // ChoiceButtonWindows, and this array holds whichever kind a given
    // visit is actually showing.
    private var choiceWindows: [NSPanel] = []
    private var handleWindow: DockedButterflyHandleWindow?
    private var edge: ScreenEdge
    private var positionFraction: Double?
    private var dragStartCenter: CGPoint?
    private var visitID = 0
    private let windowTracker = WindowTracker()
    private(set) var followsActiveWindow = false
    private var activeWindowFrame: CGRect?

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
        windowTracker.stop()
        removeButterflyAndVisit()
        window.orderOut(nil)
    }

    func parkNow(pinnedAssetIndex: Int?, displayWidth: CGFloat) { _ = ensureParked(pinnedAssetIndex: pinnedAssetIndex, displayWidth: displayWidth) }

    /// Switches between docking to a fixed screen edge and following
    /// whichever window is currently frontmost — polled every 0.4s via
    /// WindowTracker (no Accessibility/Screen Recording permission
    /// needed, since only window bounds are read, never titles or
    /// content). Dragging doesn't apply while following a window (the
    /// position is automatic), so handleDrag/handleDragEnd become no-ops
    /// below; clicking to dismiss still works either way.
    func setFollowsActiveWindow(_ follows: Bool) {
        guard follows != followsActiveWindow else { return }
        followsActiveWindow = follows
        if follows {
            windowTracker.onFrameChange = { [weak self] frame in
                self?.activeWindowFrame = frame
                self?.repositionForTrackedWindow()
            }
            windowTracker.start()
        } else {
            windowTracker.stop()
            activeWindowFrame = nil
        }
    }

    /// Smoothly moves the parked (not mid-visit) butterfly to the newly
    /// tracked window's corner. Mid-visit repositioning is skipped
    /// entirely — the message is anchored to wherever the butterfly was
    /// when it appeared, and yanking it to a different window under an
    /// open message would be jarring rather than helpful.
    private func repositionForTrackedWindow() {
        guard followsActiveWindow, !isBusy, let butterfly else { return }
        let target = dockPoint(margin: 40)
        let targetOrigin = CGPoint(x: target.x - butterfly.frame.width / 2, y: target.y - butterfly.frame.height / 2)
        guard targetOrigin != butterfly.frame.origin else { return }
        butterfly.layer?.removeAllAnimations()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            butterfly.animator().setFrameOrigin(targetOrigin)
        }, completionHandler: { [weak self] in
            self?.updateHandleWindowFrame()
        })
    }

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

    /// A razor-exact half clip (center.x precisely at 0 or screenWidth) read
    /// as slightly too little of the butterfly to recognize, especially
    /// with the wing-flutter's 3D perspective in motion — shifting the
    /// anchor this far onto the screen shows a bit more than half without
    /// losing the "perched right on the border" read.
    private static let edgeDockVisibleBias: CGFloat = 10

    /// Left/right docking pins the butterfly's center just past the screen
    /// edge so a bit more than half of it renders past the window's own
    /// bounds and is naturally clipped — it reads as perched on the border
    /// rather than floating just inside it. Top/bottom keep the original
    /// fully-visible, margin-inset placement. When the user has dragged the
    /// butterfly to a specific spot, that fraction wins over the usual
    /// random placement along the edge.
    private func dockPoint(margin: CGFloat) -> CGPoint {
        if followsActiveWindow {
            guard let activeWindowFrame else {
                // No active window found yet (the desktop itself is
                // focused, or the frontmost app has no on-screen windows)
                // — the screen's own top-right corner is a sensible place
                // to wait rather than the butterfly having nowhere to be.
                return CGPoint(x: screenFrame.width - margin, y: screenFrame.height - margin)
            }
            // The window's own top-right corner — letting the butterfly
            // straddle it naturally, since (unlike a screen edge) nothing
            // clips against another app's window bounds.
            return CGPoint(x: activeWindowFrame.maxX, y: activeWindowFrame.maxY)
        }
        switch edge {
        case .left, .right:
            let y = positionFraction.map { CGFloat($0) * screenFrame.height }
                ?? (screenFrame.height * CGFloat.random(in: 0.2...0.8))
            let x = edge == .left ? Self.edgeDockVisibleBias : screenFrame.width - Self.edgeDockVisibleBias
            return CGPoint(x: x, y: clamp(y, 20, screenFrame.height - 20))
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

    /// True only for the screen-edge case that actually gets hard-clipped
    /// by the window's own bounds — top/bottom docking and "follow active
    /// window" both show the whole butterfly, so neither needs the
    /// enlarged size or gentler flutter this compensates with.
    private var isEdgeClipped: Bool { !followsActiveWindow && (edge == .left || edge == .right) }

    private func ensureParked(pinnedAssetIndex: Int?, displayWidth: CGFloat) -> ButterflyView? {
        if let butterfly { return butterfly }
        guard let host = window.contentView else { return nil }
        // A razor-half clip of a small butterfly reads as barely
        // recognizable, more so once the wing-flutter's perspective is
        // moving — sized up so the visible portion still reads clearly as
        // "a butterfly perched here" rather than an ambiguous sliver.
        let effectiveWidth = isEdgeClipped ? displayWidth * 1.25 : displayWidth
        let view = ButterflyView(
            center: dockPoint(margin: 40),
            pinnedAssetIndex: pinnedAssetIndex,
            displayWidth: effectiveWidth,
            edgeClipped: isEdgeClipped
        )
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
        guard !followsActiveWindow, let butterfly else { return }
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
        guard !followsActiveWindow, let butterfly else { return }
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
            // The slider and the zero-tap styles all reserve one
            // full-width strip rather than one slot per choice.
            choiceLabels = checkIn.style.needsSingleReservedStrip ? [""] : checkIn.choices.map { $0.label }
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
            if let checkIn, checkIn.style == .energySlider {
                let slider = EnergySliderWindow(frame: choiceFrameOnScreen(0)) { stage in
                    let choice = checkIn.choices[stage]
                    bubble.setLiveText("\(choice.label)  \(choice.replies.randomElement() ?? choice.replies[0])")
                } onCommit: { fraction in
                    CheckInStore.record(style: checkIn.style.rawValue, choice: "\(Int((fraction * 100).rounded()))")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        leaveNow()
                    }
                }
                choiceWindows = [slider]
            } else if let checkIn, checkIn.style == .breatheWithMe {
                butterfly.setFlutterRate(0.35)
                bubble.startBreathing {
                    butterfly.setFlutterRate(1.0)
                    bubble.setLiveText(CheckInContent.randomBreathingClosingLine())
                }
            } else if let checkIn, checkIn.style == .eyeRestReset {
                bubble.startCountdownRing(seconds: 20) { remaining in
                    bubble.setLiveText("Look away… \(remaining)")
                } completion: {
                    bubble.setLiveText(CheckInContent.randomEyeRestClosingLine())
                }
            } else if let checkIn {
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
                butterfly.setFlutterRate(1.0)
                self.closeWindow?.fadeOutAndOrderOut(duration: BubbleView.fadeOutDuration)
                self.choiceWindows.forEach { $0.fadeOutAndOrderOut(duration: BubbleView.fadeOutDuration) }
                bubble.fadeOut {
                    self.closeWindow = nil
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
                if let checkIn, checkIn.style == .energySlider {
                    let slider = EnergySliderWindow(frame: choiceFrameOnScreen(0)) { stage in
                        let choice = checkIn.choices[stage]
                        bubble.setLiveText("\(choice.label)  \(choice.replies.randomElement() ?? choice.replies[0])")
                    } onCommit: { fraction in
                        CheckInStore.record(style: checkIn.style.rawValue, choice: "\(Int((fraction * 100).rounded()))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            leaveNow()
                        }
                    }
                    self.choiceWindows = [slider]
                } else if let checkIn, checkIn.style == .breatheWithMe {
                    butterfly.setFlutterRate(0.35)
                    bubble.startBreathing {
                        butterfly.setFlutterRate(1.0)
                        bubble.setLiveText(CheckInContent.randomBreathingClosingLine())
                    }
                } else if let checkIn, checkIn.style == .eyeRestReset {
                    bubble.startCountdownRing(seconds: 20) { remaining in
                        bubble.setLiveText("Look away… \(remaining)")
                    } completion: {
                        bubble.setLiveText(CheckInContent.randomEyeRestClosingLine())
                    }
                } else if let checkIn {
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
                    butterfly.setFlutterRate(1.0)
                    self.closeWindow?.fadeOutAndOrderOut(duration: BubbleView.fadeOutDuration)
                    self.choiceWindows.forEach { $0.fadeOutAndOrderOut(duration: BubbleView.fadeOutDuration) }
                    bubble.fadeOut {
                        self.closeWindow = nil
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
