import AppKit

/// Shared fade-to-invisible for the small satellite windows (choice chips,
/// the close mark) that sit on top of a BubbleView card. Without this they
/// were being `orderOut` the instant the card's own fade-out finished,
/// which meant they sat at full opacity, floating with no card behind them,
/// for the entire ~0.3s the card took to dissolve, then popped away all at
/// once — instead of leaving together with it.
extension NSWindow {
    func fadeOutAndOrderOut(duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}
