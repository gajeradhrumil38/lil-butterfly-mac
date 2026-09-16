import AppKit

/// A small interactive target for the bubble's close mark. The full-screen
/// overlay remains click-through; this window only occupies the close mark.
final class BubbleCloseWindow: NSPanel {

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
        button.target = self
        button.action = #selector(closeTapped)
        contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView?.addSubview(button)

        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func closeTapped() {
        onClick()
        orderOut(nil)
    }
}
