import AppKit

/// The interactive hit-target for the docked butterfly. The full-screen
/// overlay stays click-through everywhere else; this tiny window sits only
/// over the parked butterfly's visible bounds so a click can dismiss it and
/// a drag can move it along its edge, following the same pattern as
/// BubbleCloseWindow.
final class DockedButterflyHandleWindow: NSPanel {

    private let dragView: DragTrackingView

    init(frame: NSRect, onDrag: @escaping (CGFloat, CGFloat) -> Void, onDragEnd: @escaping () -> Void, onClick: @escaping () -> Void) {
        dragView = DragTrackingView(frame: NSRect(origin: .zero, size: frame.size))
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

        dragView.onDrag = onDrag
        dragView.onDragEnd = onDragEnd
        dragView.onClick = onClick
        contentView = dragView

        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Distinguishes a plain click (no meaningful movement) from a drag, and
/// reports drag deltas in screen points as the mouse moves.
private final class DragTrackingView: NSView {
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var onClick: (() -> Void)?

    private var dragStart: NSPoint?
    private var didDrag = false
    private let dragThreshold: CGFloat = 4

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let location = event.locationInWindow
        let dx = location.x - dragStart.x
        let dy = location.y - dragStart.y
        if !didDrag, hypot(dx, dy) > dragThreshold {
            didDrag = true
        }
        if didDrag {
            onDrag?(dx, dy)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if didDrag {
            onDragEnd?()
        } else {
            onClick?()
        }
    }
}
