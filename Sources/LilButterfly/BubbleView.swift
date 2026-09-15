import AppKit

final class BubbleView: NSView {

    private let effectView = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")
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

        label.stringValue = message
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 4
        label.alignment = .left
        label.alphaValue = 0 // revealed after the typing-dots beat, see revealText()
        addSubview(label)

        // NSTextField's sizeToFit() doesn't reliably account for
        // preferredMaxLayoutWidth when wrapping to multiple lines (it's an
        // Auto Layout hint; sizeToFit() is the older frame-based API), so it
        // can hand back a height sized for fewer lines than the text will
        // actually wrap into at this width — clipping the last line(s).
        // Measuring with boundingRect(with:options:) against the real
        // wrapping width is the reliable way to size a multi-line label.
        let maxWidth: CGFloat = 280
        // 14pt left inset + 26pt on the right to clear the close (✕) button
        // that sits in the top-right corner (see closeTargetFrame above).
        let horizontalPadding: CGFloat = 40
        let maxTextWidth = maxWidth - horizontalPadding
        label.preferredMaxLayoutWidth = maxTextWidth

        // Two independent height estimates, and we take the taller: plain
        // NSString.boundingRect() measures by font metrics alone and can
        // come up short for text containing emoji (the messages use quite a
        // few), since color-emoji glyphs don't always report the same
        // advance width boundingRect assumes — while intrinsicContentSize
        // goes through the label's real cell layout (the same path that
        // will actually render it) but only reports a wrapped height once
        // preferredMaxLayoutWidth is set, which we've just done above.
        // Occasionally seeing the last line clipped was this mismatch.
        let font = label.font ?? NSFont.systemFont(ofSize: 13)
        let measured = (message as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let maxTextHeight = lineHeight * CGFloat(label.maximumNumberOfLines)
        let intrinsicHeight = label.intrinsicContentSize.height
        let textWidth = min(ceil(measured.width), maxTextWidth)
        let textHeight = min(ceil(max(measured.height, intrinsicHeight)), maxTextHeight)

        let width = min(maxWidth, textWidth + horizontalPadding)
        let height = textHeight + 20
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.layer?.cornerRadius = height / 2 // full pill/capsule shape
        effectView.layer?.sublayers?.first(where: { $0 is CAGradientLayer })?.frame = effectView.bounds
        tail.frame = CGRect(x: -4, y: height / 2 - 6, width: 12, height: 12) // vertically centered on the pill
        label.frame = CGRect(x: 14, y: 10, width: width - horizontalPadding, height: textHeight)

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
