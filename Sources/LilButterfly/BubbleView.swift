import AppKit

final class BubbleView: NSView {

    private let effectView = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")

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
        label.preferredMaxLayoutWidth = maxWidth - 28
        label.sizeToFit()
        let width = min(maxWidth, label.frame.width + 28)
        let height = label.frame.height + 20
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        label.frame = CGRect(x: 14, y: 10, width: width - 28, height: label.frame.height)
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

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
