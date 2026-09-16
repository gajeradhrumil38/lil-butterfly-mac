import AppKit

/// A fully invisible, click-only hit target covering an entire message
/// bubble — used only for bubbles that carry an action (currently the
/// update reminder). Unlike BubbleCloseWindow, this draws nothing of its
/// own: the bubble's small close (x) mark stays the only visible affordance,
/// and tapping anywhere else on the card triggers the action instead.
final class BubbleTapWindow: NSPanel {

    private let onClick: () -> Void

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

        let button = NSButton(frame: NSRect(origin: .zero, size: frame.size))
        button.title = ""
        button.isBordered = false
        button.bezelStyle = .inline
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
