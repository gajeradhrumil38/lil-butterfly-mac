import AppKit

final class BubbleView: NSView {

    private let effectView = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let tail = NSView()
    private var didDismiss = false

    init(message: String) {
        super.init(frame: .zero)
        wantsLayer = true
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
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

        closeButton.title = "×"
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(dismissTapped)
        addSubview(closeButton)

        let maxWidth: CGFloat = 220
        label.preferredMaxLayoutWidth = maxWidth - 48
        label.sizeToFit()
        let width = min(maxWidth, label.frame.width + 48)
        let height = label.frame.height + 20
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        label.frame = CGRect(x: 14, y: 10, width: width - 42, height: label.frame.height)
        closeButton.frame = CGRect(x: width - 27, y: height - 25, width: 20, height: 20)
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    func pointTailTowardButterfly(onRight: Bool) {
        tail.frame.origin.x = onRight ? frame.width - 8 : -4
    }

    @objc private func dismissTapped() {
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
