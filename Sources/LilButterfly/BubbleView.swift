import AppKit

final class BubbleView: NSView {

    private let label = NSTextField(labelWithString: "")

    init(message: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = 14
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        alphaValue = 0

        label.stringValue = message
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor(calibratedWhite: 0.23, alpha: 1)
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
