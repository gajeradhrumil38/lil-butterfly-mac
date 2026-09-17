import AppKit

/// A small interactive target for the bubble's close mark. The full-screen
/// overlay remains click-through; this window only occupies the close mark.
///
/// The clickable area (`frame`, from BubbleView.closeTargetFrame) is
/// deliberately bigger than the visible × glyph — a precise 20x20 corner
/// target was reported hard to actually land a click on. The button fills
/// this whole bigger area invisibly; a separate, purely decorative image
/// view draws the actual × mark pinned to its original small size and
/// position, so the visible design doesn't change at all, only how
/// forgiving it is to click.
final class BubbleCloseWindow: NSPanel {

    private let onClick: () -> Void
    private weak var icon: NSImageView?

    init(frame: NSRect, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(
            contentRect: frame,
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

        let contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        self.contentView = contentView

        let button = CloseMarkButton(frame: NSRect(origin: .zero, size: frame.size))
        button.title = ""
        button.isBordered = false
        button.imagePosition = .noImage
        button.autoresizingMask = [.width, .height]
        button.target = self
        button.action = #selector(closeTapped)
        contentView.addSubview(button)

        // Pinned to the frame's own top-right corner at its original fixed
        // size — however much bigger `frame` (the hit area) is than this,
        // the visible mark itself never moves or grows. ClickThroughImageView
        // opts out of hit-testing: a plain NSImageView sitting on top of the
        // button would otherwise silently swallow every click that landed
        // exactly on the visible × (precisely where anyone would naturally
        // aim) before it ever reached the button underneath.
        let visibleSize: CGFloat = 20
        let icon = ClickThroughImageView(frame: NSRect(
            x: frame.width - visibleSize, y: frame.height - visibleSize,
            width: visibleSize, height: visibleSize
        ))
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        icon.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close message")?
            .withSymbolConfiguration(symbolConfig)
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        icon.imageScaling = .scaleProportionallyDown
        icon.wantsLayer = true
        contentView.addSubview(icon)
        self.icon = icon

        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func closeTapped() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        animateClickFeedback()
        onClick()
        // No `orderOut(nil)` here — onClick() triggers the overlay's
        // leaveNow(), which fades this same window out via
        // fadeOutAndOrderOut alongside the card. An immediate synchronous
        // orderOut here used to beat that fade to the punch, hiding the
        // mark instantly instead of dissolving with everything else — and
        // would have hidden this click animation before it could ever be
        // seen, too.
    }

    /// A quick scale-up and full-brightness flash on the visible mark
    /// itself — the same "this registered" feedback ChoiceButtonWindow's
    /// chips give, so tapping close reads as an actual press rather than
    /// nothing visibly happening until the card starts fading a moment
    /// later.
    private func animateClickFeedback() {
        guard let icon else { return }
        icon.contentTintColor = .white
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DIdentity
        animation.toValue = CATransform3DMakeScale(1.3, 1.3, 1)
        animation.duration = 0.15
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        icon.layer?.add(animation, forKey: "closeTap")
        icon.layer?.transform = CATransform3DMakeScale(1.3, 1.3, 1)
    }
}

/// A pointing-hand cursor while hovering, via NSTrackingArea rather than
/// resetCursorRects — cursor *rects* are only actually honored while a
/// window is key, and this panel (like every other interactive window in
/// this app) deliberately overrides canBecomeKey to false so it never
/// steals focus. NSTrackingArea's mouseEntered/mouseExited fire regardless
/// of key status, which is why ChoiceButtonWindow's HoverButton already
/// uses the same approach for its own hover feedback.
private final class CloseMarkButton: NSButton {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // .set() rather than .push()/.pop() — this window can disappear (the
    // card fading out) while the mouse is still technically inside it,
    // which would never fire mouseExited to balance a push, leaving the
    // hand cursor stuck. .set() has no stack to unbalance; the next view
    // the mouse moves over sets its own cursor regardless.
    override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
}

/// A decorative-only image view — always reports "nothing here" to
/// hit-testing so clicks pass straight through to whatever sits behind it.
private final class ClickThroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
