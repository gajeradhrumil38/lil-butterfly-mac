import AppKit

/// A small, real macOS-style button attached just below a message bubble —
/// used only for actionable messages (currently the update reminder).
/// Replaces an earlier attempt at an invisible full-card tap region, which
/// wasn't reliably clickable and gave no visible affordance; this follows
/// the same proven approach BubbleCloseWindow already uses for the (x) —
/// one small window draws its own real, visible control and handles its
/// own click, rather than separating "what's drawn" from "what's clickable."
final class UpdateActionButtonWindow: NSPanel {

    private let onClick: () -> Void

    init(frame: CGRect, title: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]

        let button = NSButton(frame: NSRect(origin: .zero, size: frame.size))
        button.title = title
        button.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        button.isBordered = false
        button.contentTintColor = .white
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: button.font as Any, .foregroundColor: NSColor.white]
        )
        button.wantsLayer = true
        button.layer?.cornerRadius = frame.height / 2
        button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
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
