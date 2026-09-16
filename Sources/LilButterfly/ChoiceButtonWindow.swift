import AppKit

/// A small window that draws exactly one visible, tappable control and
/// handles its own click — the fix that solved an earlier bug where an
/// invisible full-card tap region and the close mark's separately-drawn (x)
/// visually conflicted. Every interactive element in a bubble body (the
/// update button, and every check-in choice) is one of these: what's drawn
/// and what's clickable are always the same window, never split into two.
final class ChoiceButtonWindow: NSPanel {

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
    }

    private let onClick: () -> Void

    init(frame: NSRect, title: String, style: Style = .accentCapsule, onClick: @escaping () -> Void) {
        self.onClick = onClick
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
        button.wantsLayer = true
        button.layer?.cornerRadius = style.cornerRadius
        button.layer?.backgroundColor = style.hasBackground ? style.backgroundColor.cgColor : nil
        button.autoresizingMask = [.width, .height]
        button.target = self
        button.action = #selector(tapped)
        contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView?.addSubview(button)

        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func tapped() {
        onClick()
        orderOut(nil)
    }
}
