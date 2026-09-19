import AppKit

/// The one check-in style that needs a live-updating control instead of N
/// discrete choices — a real draggable track, not five separate tap
/// targets. Same "one small window draws and handles its own click (or
/// drag)" shape as ChoiceButtonWindow, just with continuous input: as the
/// thumb moves, the caller is told which of 5 stages it's now in (so it can
/// morph the bubble's emoji/message live) and, on release, the exact
/// fraction (for logging).
final class EnergySliderWindow: NSPanel {

    private weak var track: EnergyTrackView?

    /// Small fixed headroom for the thumb's own drag-press grow animation
    /// and its drop shadow — both are tiny relative to the track, unlike
    /// ChoiceButtonWindow's per-button dynamic sizing, so a flat constant
    /// is enough here.
    private static let headroom: CGFloat = 8

    init(
        frame: NSRect,
        initialFraction: Double = 0.5,
        onStageChange: @escaping (Int) -> Void,
        onCommit: @escaping (Double) -> Void
    ) {
        super.init(
            contentRect: frame.insetBy(dx: -Self.headroom, dy: -Self.headroom),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]

        let track = EnergyTrackView(
            frame: NSRect(x: Self.headroom, y: Self.headroom, width: frame.width, height: frame.height),
            initialFraction: initialFraction
        )
        var lastStage = -1
        track.onLiveChange = { fraction in
            let stage = CheckInContent.energyStageIndex(for: fraction)
            if stage != lastStage {
                lastStage = stage
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                onStageChange(stage)
            }
        }
        track.onCommit = { fraction in onCommit(fraction) }
        self.track = track

        contentView = NSView(frame: NSRect(origin: .zero, size: frame.insetBy(dx: -Self.headroom, dy: -Self.headroom).size))
        contentView?.addSubview(track)

        orderFrontRegardless()
        // NSTrackingArea only fires mouseEntered when the cursor actually
        // moves into a region — a stationary cursor already over this
        // spot when the window appears never gets that transition, so the
        // hand cursor would never show. Checking the actual cursor
        // position the moment this window appears covers that case.
        if frame.contains(NSEvent.mouseLocation) {
            NSCursor.pointingHand.set()
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect.insetBy(dx: -Self.headroom, dy: -Self.headroom), display: flag)
        track?.frame = NSRect(x: Self.headroom, y: Self.headroom, width: frameRect.width, height: frameRect.height)
        if frameRect.contains(NSEvent.mouseLocation) {
            NSCursor.pointingHand.set()
        }
    }
}

/// Draws and drags the track itself. Deliberately hand-rolled instead of
/// NSSlider — NSSlider's default appearance doesn't take a custom
/// color-fill gradient without fighting its cell drawing, and every other
/// interactive control in this app already follows the "own its click
/// region, draw exactly what's clickable" pattern.
private final class EnergyTrackView: NSView {
    var onLiveChange: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?
    private(set) var fraction: Double

    private let trackLayer = CALayer()
    private let fillGradient = CAGradientLayer()
    private let fillMask = CALayer()
    private let thumbLayer = CALayer()

    private let thumbDiameter: CGFloat = 18
    private let trackHeight: CGFloat = 8
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, initialFraction: Double) {
        self.fraction = initialFraction
        super.init(frame: frame)
        wantsLayer = true

        trackLayer.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.addSublayer(trackLayer)

        // The gradient's own frame always spans the full track — only the
        // mask's width grows with `fraction` — so the color at a given
        // physical position stays fixed as the thumb passes it (a "cool to
        // warm" charge readout), instead of the whole gradient stretching
        // and every color shifting each time the fraction changes.
        fillGradient.colors = [NSColor.systemTeal.cgColor, NSColor.systemOrange.cgColor]
        fillGradient.startPoint = CGPoint(x: 0, y: 0.5)
        fillGradient.endPoint = CGPoint(x: 1, y: 0.5)
        fillMask.backgroundColor = NSColor.black.cgColor
        fillGradient.mask = fillMask
        layer?.addSublayer(fillGradient)

        thumbLayer.backgroundColor = NSColor.white.cgColor
        thumbLayer.shadowColor = NSColor.black.cgColor
        thumbLayer.shadowOpacity = 0.35
        thumbLayer.shadowRadius = 2
        thumbLayer.shadowOffset = CGSize(width: 0, height: -1)
        layer?.addSublayer(thumbLayer)
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let t = trackRect
        trackLayer.frame = t
        trackLayer.cornerRadius = t.height / 2
        fillGradient.frame = t
        updatePositions()
        CATransaction.commit()
    }

    private var trackRect: CGRect {
        let inset = thumbDiameter / 2
        return CGRect(x: inset, y: (bounds.height - trackHeight) / 2, width: max(1, bounds.width - inset * 2), height: trackHeight)
    }

    private func updatePositions() {
        let t = trackRect
        fillMask.frame = CGRect(x: 0, y: 0, width: t.width * CGFloat(fraction), height: t.height)
        let thumbCenter = CGPoint(x: t.minX + t.width * CGFloat(fraction), y: bounds.height / 2)
        thumbLayer.frame = CGRect(
            x: thumbCenter.x - thumbDiameter / 2, y: thumbCenter.y - thumbDiameter / 2,
            width: thumbDiameter, height: thumbDiameter
        )
        thumbLayer.cornerRadius = thumbDiameter / 2
    }

    private func setFraction(fromEventAt point: CGPoint) {
        let t = trackRect
        let newFraction = Double(min(1, max(0, (point.x - t.minX) / t.width)))
        guard newFraction != fraction else { return }
        fraction = newFraction
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updatePositions()
        CATransaction.commit()
        onLiveChange?(fraction)
    }

    private func animateThumb(pressed: Bool) {
        let scale: CGFloat = pressed ? 1.25 : 1.0
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = thumbLayer.presentation()?.transform ?? CATransform3DIdentity
        animation.toValue = CATransform3DMakeScale(scale, scale, 1)
        animation.duration = 0.15
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        thumbLayer.add(animation, forKey: "press")
        thumbLayer.transform = CATransform3DMakeScale(scale, scale, 1)
    }

    override func mouseDown(with event: NSEvent) {
        setFraction(fromEventAt: convert(event.locationInWindow, from: nil))
        animateThumb(pressed: true)
    }

    override func mouseDragged(with event: NSEvent) {
        setFraction(fromEventAt: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        setFraction(fromEventAt: convert(event.locationInWindow, from: nil))
        animateThumb(pressed: false)
        onCommit?(fraction)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // .set() rather than resetCursorRects/addCursorRect — cursor *rects*
    // only actually take effect while a window is key, and this panel (like
    // every other interactive window in this app) deliberately never
    // becomes key, so that mechanism silently did nothing here. Reasserted
    // on every mouseMoved too — a single .set() on entry can get silently
    // reset by unrelated Core Animation activity nearby (a documented
    // AppKit quirk), which read as the hand cursor working only sometimes.
    override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
}
