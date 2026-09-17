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

    static func style(for checkInStyle: CheckInStyle) -> Style {
        switch checkInStyle {
        case .smilePrompt, .gratitudeTap, .pickAWord: return .textChip
        case .moodPicker, .favoriteColor: return .plainChip
        }
    }

    static func feedback(for checkInStyle: CheckInStyle) -> Feedback {
        switch checkInStyle {
        case .smilePrompt, .gratitudeTap, .pickAWord: return .selectedChip
        case .moodPicker, .favoriteColor: return .scale
        }
    }

    private let onClick: () -> Void
    private let dismissesOnClick: Bool
    private let feedback: Feedback
    private weak var button: NSButton?

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
        super.init(
            contentRect: frame,
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

        let button = NSButton(frame: NSRect(origin: .zero, size: frame.size))
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
        button.autoresizingMask = [.width, .height]
        button.target = self
        button.action = #selector(tapped)
        self.button = button
        contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView?.addSubview(button)

        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func tapped() {
        animateFeedback()
        onClick()
        if dismissesOnClick {
            orderOut(nil)
        }
    }

    private func animateFeedback() {
        guard let button, feedback != .none else { return }
        if feedback == .selectedChip {
            button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
            button.layer?.cornerRadius = 10
        }
        let scale: CGFloat = feedback == .selectedChip ? 1.08 : 1.16
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DIdentity
        animation.toValue = CATransform3DMakeScale(scale, scale, 1)
        animation.duration = 0.18
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        button.layer?.add(animation, forKey: "choiceFeedback")
        button.layer?.transform = CATransform3DMakeScale(scale, scale, 1)
    }
}
