import AppKit

/// A small window that draws exactly one visible, tappable control and
/// handles its own click — the fix that solved an earlier bug where an
/// invisible full-card tap region and the close mark's separately-drawn (x)
/// visually conflicted. Every interactive element in a bubble body (the
/// update button, and every check-in choice) is one of these: what's drawn
/// and what's clickable are always the same window, never split into two.
final class ChoiceButtonWindow: NSPanel {

    enum Feedback {
        case none
        case scale
        case selectedChip

        var hoverScale: CGFloat {
            switch self {
            case .none: return 1
            case .scale: return 1.12
            case .selectedChip: return 1
            }
        }

        var clickScale: CGFloat {
            switch self {
            case .none: return 1
            case .scale: return 1.3
            case .selectedChip: return 1.06
            }
        }

        /// The biggest transform this feedback ever applies (hover or
        /// click) — used to size this window's headroom so nothing gets
        /// clipped at its own edge no matter which state is showing.
        var maxScale: CGFloat { max(hoverScale, clickScale) }
    }

    /// Visual style for the button's own content — lets the same window
    /// type render either the update reminder's filled accent capsule or a
    /// plain emoji/word chip with no background of its own.
    struct Style {
        var backgroundColor: NSColor
        var textColor: NSColor
        var font: NSFont
        var cornerRadius: CGFloat
        var hasBackground: Bool

        /// The update reminder's existing look, unchanged.
        static let accentCapsule = Style(
            backgroundColor: .controlAccentColor,
            textColor: .white,
            font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
            cornerRadius: 14,
            hasBackground: true
        )

        /// Just the label, no fill — for emoji and word choices sitting in
        /// a row of several.
        static let plainChip = Style(
            backgroundColor: .clear,
            textColor: .white,
            font: NSFont.systemFont(ofSize: 18, weight: .regular),
            cornerRadius: 0,
            hasBackground: false
        )

        /// A real filled pill, matching the brainstorming mockups' chip
        /// look — not just floating text. `.clear`/`hasBackground: false`
        /// (the previous version) rendered no visible chip boundary at all.
        static let textChip = Style(
            backgroundColor: NSColor(calibratedWhite: 0.227, alpha: 1),
            textColor: .white,
            font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
            cornerRadius: 10,
            hasBackground: true
        )
    }

    // Zero-tap styles (breatheWithMe, eyeRestReset) never build a
    // ChoiceButtonWindow at all, but these switches stay exhaustive over
    // every CheckInStyle regardless — mapped to .plainChip/.scale here is
    // simply unreachable in practice for them.
    static func style(for checkInStyle: CheckInStyle) -> Style {
        switch checkInStyle {
        case .smilePrompt, .gratitudeTap, .pickAWord: return .textChip
        case .moodPicker, .favoriteColor, .energySlider, .breatheWithMe, .eyeRestReset: return .plainChip
        }
    }

    static func feedback(for checkInStyle: CheckInStyle) -> Feedback {
        switch checkInStyle {
        case .smilePrompt, .gratitudeTap, .pickAWord: return .selectedChip
        case .moodPicker, .favoriteColor, .energySlider, .breatheWithMe, .eyeRestReset: return .scale
        }
    }

    private let onClick: () -> Void
    private let dismissesOnClick: Bool
    private let feedback: Feedback
    private let style: Style
    private weak var button: HoverButton?
    private var isTapped = false

    /// Extra space kept around the button's visual (resting) frame inside
    /// this window — sized to whatever this particular button's own
    /// feedback actually scales up to, not a flat guess. A fixed 5pt was
    /// enough for a small emoji but not for a wide, long-label text chip
    /// scaling by the same ratio (a wider button grows more pixels per
    /// point of scale) — pixels transformed past a window's own frame
    /// simply aren't drawn, regardless of any layer's masksToBounds
    /// setting, so undersizing this for a bigger button is exactly what
    /// read as the selected chip getting "cut off".
    private let headroom: CGFloat

    private static func headroom(for frame: NSRect, feedback: Feedback) -> CGFloat {
        guard feedback.maxScale > 1 else { return 4 }
        let growth = max(frame.width, frame.height) * (feedback.maxScale - 1) / 2
        return ceil(growth) + 6
    }

    init(
        frame: NSRect,
        title: String,
        style: Style = .accentCapsule,
        dismissesOnClick: Bool = true,
        feedback: Feedback = .none,
        onClick: @escaping () -> Void
    ) {
        self.onClick = onClick
        self.dismissesOnClick = dismissesOnClick
        self.feedback = feedback
        self.style = style
        let headroom = Self.headroom(for: frame, feedback: feedback)
        self.headroom = headroom
        super.init(
            contentRect: frame.insetBy(dx: -headroom, dy: -headroom),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = style.hasBackground
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]

        let button = HoverButton(frame: NSRect(x: headroom, y: headroom, width: frame.width, height: frame.height))
        button.title = title
        button.isBordered = false
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: style.font, .foregroundColor: style.textColor]
        )
        // Without this, NSButtonCell wraps a title too long for one line
        // onto a second line instead of truncating it — and since these
        // buttons are only ~32pt tall, that second line just gets clipped
        // off, showing "A good conversation" as "A" or "Something I
        // finished" as "So". Single-line + tail-truncation keeps whatever
        // fits on one line, with an ellipsis if it's ever cut short,
        // instead of silently dropping the rest of the word.
        button.cell?.usesSingleLineMode = true
        button.cell?.lineBreakMode = .byTruncatingTail
        button.wantsLayer = true
        button.layer?.cornerRadius = style.cornerRadius
        button.layer?.backgroundColor = style.hasBackground ? style.backgroundColor.cgColor : nil
        button.target = self
        button.action = #selector(tapped)
        button.onHoverChange = { [weak self] isInside in self?.hoverChanged(isInside) }
        self.button = button
        contentView = NSView(frame: NSRect(origin: .zero, size: frame.insetBy(dx: -headroom, dy: -headroom).size))
        contentView?.addSubview(button)

        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Repositioning (as the bubble moves) always targets the visual
    /// resting frame — keep applying the same headroom expansion so the
    /// button's on-screen position stays correct and the scale headroom
    /// survives every reposition, not just the initial placement.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect.insetBy(dx: -headroom, dy: -headroom), display: flag)
        button?.frame = NSRect(x: headroom, y: headroom, width: frameRect.width, height: frameRect.height)
    }

    private func hoverChanged(_ isInside: Bool) {
        guard let button, feedback.hoverScale > 1, !isTapped else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            button.animator().layer?.setAffineTransform(
                isInside ? CGAffineTransform(scaleX: feedback.hoverScale, y: feedback.hoverScale) : .identity
            )
        }
    }

    @objc private func tapped() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        animateFeedback()
        onClick()
        if dismissesOnClick {
            orderOut(nil)
        }
    }

    private func animateFeedback() {
        guard let button, feedback != .none else { return }
        isTapped = true
        if feedback == .selectedChip {
            button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
            button.layer?.cornerRadius = 10
        }
        let scale = feedback.clickScale
        let animation = CASpringAnimation(keyPath: "transform")
        animation.fromValue = button.layer?.presentation()?.transform ?? CATransform3DIdentity
        animation.toValue = CATransform3DMakeScale(scale, scale, 1)
        animation.damping = 9
        animation.stiffness = 220
        animation.mass = 0.3
        animation.duration = animation.settlingDuration
        button.layer?.add(animation, forKey: "choiceFeedback")
        button.layer?.transform = CATransform3DMakeScale(scale, scale, 1)
    }
}

/// Adds hover detection to a plain NSButton. NSTrackingArea posts
/// mouseEntered/mouseExited straight to the view under the cursor, so this
/// needs an NSButton subclass rather than a closure hung off a plain
/// NSButton instance.
private final class HoverButton: NSButton {
    var onHoverChange: ((Bool) -> Void)?
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

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}
