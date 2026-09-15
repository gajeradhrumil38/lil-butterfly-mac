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
            defer: false,
            screen: screen
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]

        let hostView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        hostView.wantsLayer = true
        contentView = hostView

        orderFrontRegardless()
    }

    // Belt-and-suspenders: this window must never be allowed to take focus,
    // even if something in AppKit tries to make it key.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
