import AppKit

final class BubbleView: NSView {

    private let effectView = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")
    private let tail = NSView()
    private var didDismiss = false

    /// The only interactive region gets its own tiny window so the
    /// full-screen overlay can remain click-through.
    var closeTargetFrame: CGRect {
        CGRect(x: frame.width - 31, y: frame.height - 27, width: 28, height: 28)
    }

    init(message: String) {
        super.init(frame: .zero)
        wantsLayer = true
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        let sheen = CAGradientLayer()
        sheen.colors = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            NSColor.white.withAlphaComponent(0.02).cgColor,
            NSColor.clear.cgColor,
        ]
        sheen.locations = [0, 0.28, 0.72]
        sheen.startPoint = CGPoint(x: 0.1, y: 1)
        sheen.endPoint = CGPoint(x: 0.9, y: 0)
        effectView.layer?.addSublayer(sheen)
        addSubview(effectView)

        tail.wantsLayer = true
        tail.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.82).cgColor
        tail.layer?.cornerRadius = 3
        tail.frame = CGRect(x: -4, y: 18, width: 12, height: 12)
        tail.layer?.setAffineTransform(CGAffineTransform(rotationAngle: .pi / 4))
        addSubview(tail, positioned: .below, relativeTo: effectView)

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        alphaValue = 0

        label.stringValue = message
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.alignment = .left
        addSubview(label)

        let maxWidth: CGFloat = 220
        label.preferredMaxLayoutWidth = maxWidth - 48
        label.sizeToFit()
        let width = min(maxWidth, label.frame.width + 48)
        let height = label.frame.height + 20
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.layer?.sublayers?.first(where: { $0 is CAGradientLayer })?.frame = effectView.bounds
        label.frame = CGRect(x: 14, y: 10, width: width - 42, height: label.frame.height)
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    func pointTailTowardButterfly(onRight: Bool) {
        tail.frame.origin.x = onRight ? frame.width - 8 : -4
    }

    func dismiss() {
        guard !didDismiss else { return }
        didDismiss = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.removeFromSuperview() })
    }

    func fadeIn() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            animator().alphaValue = 1
        }
    }

    func fadeOut(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            animator().alphaValue = 0
        }, completionHandler: completion)
    }
}
