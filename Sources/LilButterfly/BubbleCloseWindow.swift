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

        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        glass.material = .popover
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = frame.width / 2
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        glass.autoresizingMask = [.width, .height]

        let button = NSButton(frame: NSRect(origin: .zero, size: frame.size))
        button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close message")
        button.imagePosition = .imageOnly
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = NSColor.white.withAlphaComponent(0.82)
        button.toolTip = "Dismiss message"
        button.autoresizingMask = [.width, .height]
        button.target = self
        button.action = #selector(closeTapped)
        contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView?.addSubview(glass)
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
