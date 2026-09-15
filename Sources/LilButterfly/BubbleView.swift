import AppKit

final class BubbleView: NSView {

    private let effectView = NSVisualEffectView()
    private let label = NSTextView(frame: .zero)
    private let tail = NSView()
    private let dotsContainer = NSView()
    private var didRevealText = false

    /// The only interactive region gets its own tiny window so the
    /// full-screen overlay can remain click-through. Inset evenly from the
    /// card's top-right corner (rather than the previous frame, which
    /// overshot the card's top edge by 1pt and sat almost flush with the
    /// right edge, reading as misaligned against the card's rounded corner).
    var closeTargetFrame: CGRect {
        let size: CGFloat = 20
        let margin: CGFloat = 6
        return CGRect(x: frame.width - margin - size, y: frame.height - margin - size, width: size, height: size)
    }

    init(message: String) {
        super.init(frame: .zero)
        wantsLayer = true
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
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
        tail.layer?.setAffineTransform(CGAffineTransform(rotationAngle: .pi / 4))
        addSubview(tail, positioned: .below, relativeTo: effectView)

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        alphaValue = 0

        label.string = message
        let font = NSFont.systemFont(ofSize: 13)
        label.font = font
        label.textColor = .white
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.isRichText = false
        label.textContainerInset = .zero
        label.textContainer?.lineFragmentPadding = 0
        label.textContainer?.lineBreakMode = .byWordWrapping
        label.textContainer?.widthTracksTextView = false
        label.textContainer?.heightTracksTextView = false
        label.alphaValue = 0 // revealed after the typing-dots beat, see revealText()
        label.textStorage?.setAttributedString(NSAttributedString(
            string: message,
            attributes: [.font: font, .foregroundColor: NSColor.white]
        ))
        addSubview(label)

        let maxWidth: CGFloat = 280
        // 14pt left inset + 26pt on the right to clear the close (✕) button
        // that sits in the top-right corner (see closeTargetFrame above).
        let horizontalPadding: CGFloat = 40
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let naturalMeasured = (message as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        // Pick the compact width from the natural one-line measurement, then
        // measure again at that final width. The second pass is important:
        // resizing a medium-length sentence can create an extra wrapped line.
        let width = min(maxWidth, max(150, ceil(naturalMeasured.width) + horizontalPadding))
        let textWidth = width - horizontalPadding

        // Ask TextKit for the height of the actual laid-out glyphs. Unlike
        // NSTextField's intrinsicContentSize, this cannot silently return a
        // one-line height for a wrapped message.
        guard let textContainer = label.textContainer, let layoutManager = label.layoutManager else { return }
        textContainer.containerSize = CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let textHeight = ceil(max(usedRect.height, font.ascender - font.descender + font.leading))
        let height = textHeight + 20
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.layer?.cornerRadius = height / 2 // full pill/capsule shape
        effectView.layer?.sublayers?.first(where: { $0 is CAGradientLayer })?.frame = effectView.bounds
        tail.frame = CGRect(x: -4, y: height / 2 - 6, width: 12, height: 12) // vertically centered on the pill
        label.frame = CGRect(x: 14, y: 10, width: textWidth, height: textHeight)

        setUpDots(in: label.frame)
        addSubview(dotsContainer)
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    /// A brief "..." pulse shown in place of the text, like a chat message
    /// arriving, before revealText() cross-fades to the real message. Sized
    /// to sit within the same box the label already occupies, so the card
    /// doesn't resize/pop when the text appears.
    private func setUpDots(in labelFrame: CGRect) {
        let dotSize: CGFloat = 5
        let spacing: CGFloat = 5
        dotsContainer.frame = CGRect(
            x: labelFrame.minX, y: labelFrame.minY,
            width: dotSize * 3 + spacing * 2, height: labelFrame.height
        )
        dotsContainer.wantsLayer = true
        for i in 0..<3 {
            let dot = CALayer()
            dot.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
            dot.cornerRadius = dotSize / 2
            dot.frame = CGRect(
                x: CGFloat(i) * (dotSize + spacing),
                y: (dotsContainer.bounds.height - dotSize) / 2,
                width: dotSize, height: dotSize
            )
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.3
            pulse.toValue = 1.0
            pulse.duration = 0.5
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.beginTime = CACurrentMediaTime() + Double(i) * 0.15
            dot.add(pulse, forKey: "pulse")
            dotsContainer.layer?.addSublayer(dot)
        }
    }

    /// Cross-fades from the typing dots to the actual message text.
    private func revealText() {
        guard !didRevealText else { return }
        didRevealText = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            dotsContainer.animator().alphaValue = 0
            label.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            self?.dotsContainer.removeFromSuperview()
        })
    }

    func pointTailTowardButterfly(onRight: Bool) {
        tail.frame.origin.x = onRight ? frame.width - 8 : -4
    }

    func fadeIn() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            animator().alphaValue = 1
        }
        // Tied to fadeIn (the moment the card is actually visible) rather
        // than init, since the card is typically created well before it's
        // shown (e.g. during the fly-in animation) — timing this from init
        // would let the dots-to-text swap happen off-screen, unseen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.revealText()
        }
    }

    func fadeOut(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            animator().alphaValue = 0
        }, completionHandler: completion)
    }
}
