import AppKit

/// A borderless, transparent window that covers exactly one screen, sits
/// above normal windows (including full-screen ones), never becomes key,
/// never shows in the Dock/Cmd-Tab, and lets every click pass straight
/// through to whatever is underneath it.
final class OverlayWindow: NSWindow {

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // The host view returns a hit only for BubbleView, so the butterfly
        // and every other pixel remain click-through while the card's close
        // mark can still be used.
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]

        let hostView = ClickThroughHostView(frame: NSRect(origin: .zero, size: screen.frame.size))
        hostView.wantsLayer = true
        contentView = hostView

        orderFrontRegardless()
    }

    // Belt-and-suspenders: this window must never be allowed to take focus,
    // even if something in AppKit tries to make it key.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ClickThroughHostView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard subviews.contains(where: { view in
            view is BubbleView && view.frame.contains(point)
        }) else { return nil }
        return super.hitTest(point)
    }
}
