import AppKit

/// A small interactive target for the bubble's close mark. The full-screen
/// overlay remains click-through; this window only occupies the close mark.
final class BubbleCloseWindow: NSPanel {

    private let onClick: () -> Void
    private weak var button: CloseMarkButton?

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

        let button = CloseMarkButton(frame: NSRect(origin: .zero, size: frame.size))
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close message")?
            .withSymbolConfiguration(symbolConfig)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        button.toolTip = "Dismiss message"
        button.autoresizingMask = [.width, .height]
        button.wantsLayer = true
        button.target = self
        button.action = #selector(closeTapped)
        self.button = button
        contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView?.addSubview(button)

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
        // fadeOutAndOrderOut alongside the card and any other chips. An
        // immediate synchronous orderOut here used to beat that fade to
        // the punch, hiding the mark instantly instead of dissolving with
        // everything else — and would have hidden this click animation
        // before it could ever be seen, too.
    }

    /// A quick scale-up and full-brightness flash — the same "this
    /// registered" feedback ChoiceButtonWindow's chips give, so tapping
    /// the close mark reads as an actual press rather than nothing
    /// visibly happening until the card starts fading a moment later.
    private func animateClickFeedback() {
        guard let button else { return }
        button.contentTintColor = .white
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DIdentity
        animation.toValue = CATransform3DMakeScale(1.3, 1.3, 1)
        animation.duration = 0.15
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        button.layer?.add(animation, forKey: "closeTap")
        button.layer?.transform = CATransform3DMakeScale(1.3, 1.3, 1)
    }
}

/// Shows a pointing-hand cursor while hovering — the standard AppKit way
/// (resetCursorRects, invoked automatically whenever this view's tracking
/// rects need updating) to signal "this is clickable" for a control that
/// otherwise gives no hint it's interactive against the borderless overlay
/// behind it.
private final class CloseMarkButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
