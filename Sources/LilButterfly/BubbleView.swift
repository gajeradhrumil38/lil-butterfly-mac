import AppKit

final class BubbleView: NSView {

    private let effectView = NSVisualEffectView()
    private let label = NSTextView(frame: .zero)
    private let dotsContainer = NSView()
    private var didRevealText = false

    /// Classic chat-bubble corner radius (not a full pill). Deliberately well
    /// under half the minimum card height (~36pt for a one-line message) so
    /// even short messages keep visible flat edges instead of rounding back
    /// into a capsule — a radius close to height/2 looked identical to the
    /// old pill shape for exactly that common case.
    private static let cornerRadius: CGFloat = 12

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

    private static let choiceRowHeight: CGFloat = 32
    private var choiceFrames: [CGRect] = []

    /// The rect for one choice slot in the reserved bottom row, inside the
    /// same rounded rectangle as the message — not a separate floating pill
    /// below it. The same closeTargetFrame pattern, generalized from one
    /// button (the update reminder) to N (every check-in style). A single
    /// choice keeps the update button's existing fixed 116pt-wide centered
    /// look; more than one spreads evenly across the card's content width.
    func choiceFrame(at index: Int) -> CGRect {
        guard choiceFrames.indices.contains(index) else { return .zero }
        return choiceFrames[index]
    }

    init(message: String, choiceLabels: [String] = [], checkInStyle: CheckInStyle? = nil) {
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

        let maxWidth: CGFloat = checkInStyle == .favoriteColor ? 380 : 360
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
        let minimumChoiceWidth: CGFloat
        switch checkInStyle {
        case .favoriteColor: minimumChoiceWidth = 360
        case .moodPicker: minimumChoiceWidth = 300
        default: minimumChoiceWidth = choiceLabels.isEmpty ? 0 : 270
        }
        let width = min(maxWidth, max(150, ceil(naturalMeasured.width) + horizontalPadding, minimumChoiceWidth))
        let textWidth = width - horizontalPadding

        // Ask TextKit for the height of the actual laid-out glyphs. Unlike
        // NSTextField's intrinsicContentSize, this cannot silently return a
        // one-line height for a wrapped message.
        guard let textContainer = label.textContainer, let layoutManager = label.layoutManager else { return }
        textContainer.containerSize = CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let textHeight = ceil(max(usedRect.height, font.ascender - font.descender + font.leading))
        choiceFrames = Self.makeChoiceFrames(labels: choiceLabels, width: width, style: checkInStyle)
        let rowCount = choiceFrames.reduce(into: 0) { result, choiceFrame in
            result = max(result, Int((choiceFrame.minY - 10) / (Self.choiceRowHeight + 6)) + 1)
        }
        let choiceAreaHeight: CGFloat = choiceLabels.isEmpty ? 0 : 18 + CGFloat(rowCount) * Self.choiceRowHeight + CGFloat(max(0, rowCount - 1)) * 6
        let height = textHeight + 20 + choiceAreaHeight
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.layer?.cornerRadius = min(Self.cornerRadius, height / 2)
        effectView.layer?.sublayers?.first(where: { $0 is CAGradientLayer })?.frame = effectView.bounds
        label.frame = CGRect(x: 14, y: 10 + choiceAreaHeight, width: textWidth, height: textHeight)

        setUpDots(in: label.frame)
        addSubview(dotsContainer)
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    private static func makeChoiceFrames(labels: [String], width: CGFloat, style: CheckInStyle?) -> [CGRect] {
        guard !labels.isEmpty else { return [] }
        let padding: CGFloat = 14
        let spacing: CGFloat = 6
        let contentWidth = width - padding * 2
        let isChipLayout = style == .smilePrompt || style == .gratitudeTap || style == .pickAWord
        guard isChipLayout else {
            let slotWidth = (contentWidth - spacing * CGFloat(labels.count - 1)) / CGFloat(labels.count)
            return labels.indices.map { index in
                CGRect(x: padding + CGFloat(index) * (slotWidth + spacing), y: 10, width: slotWidth, height: choiceRowHeight)
            }
        }

        let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        var result: [CGRect] = []
        var x = padding
        var y: CGFloat = 10
        for label in labels {
            let measured = (label as NSString).size(withAttributes: [.font: font])
            let chipWidth = min(contentWidth, max(58, ceil(measured.width) + 24))
            if x > padding && x + chipWidth > width - padding {
                x = padding
                y += choiceRowHeight + spacing
            }
            result.append(CGRect(x: x, y: y, width: chipWidth, height: choiceRowHeight))
            x += chipWidth + spacing
        }
        return result
    }

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

    /// Cross-fades the label to a new string — used when a check-in choice
    /// is tapped, swapping the question for a reply in place without
    /// resizing the card. Reply pools are written to stay roughly as short
    /// as the questions they follow, same convention as every other message
    /// pool in this app, since this does not re-run the height calculation
    /// from init — a much longer reply would overflow the reserved box.
    func revealReply(_ text: String) {
        // A choice can be tapped before the typing-dots-to-text reveal
        // (scheduled 0.9s after fadeIn) has run yet. dotsContainer sits on
        // top of the label in z-order, so without this, the reply text
        // gets set correctly underneath but stays hidden behind the still-
        // pulsing dots until that unrelated timer catches up — reading as
        // if the click did nothing (or the message "vanished") for up to
        // 0.9s. Marking didRevealText here makes that scheduled reveal a
        // no-op, and removing dotsContainer immediately guarantees the
        // reply is visible the moment this fade-in completes.
        didRevealText = true
        dotsContainer.removeFromSuperview()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            label.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            let font = NSFont.systemFont(ofSize: 13)
            self.label.textStorage?.setAttributedString(NSAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: NSColor.white]
            ))
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.label.animator().alphaValue = 1
            }
        })
    }
}
