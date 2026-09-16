import AppKit

/// A discrete, tick-stopped slider for picking one of ButterflySize.widths,
/// hosted as an NSMenuItem's view the same way IntervalSliderView is. Shows
/// a small live preview (always the same design, so only size varies) that
/// grows/shrinks with the slider, so the choice is visual rather than just a
/// label like "Large".
final class SizeSliderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let minimumImageView = NSImageView()
    private let previewImageView = NSImageView()
    let slider = NSSlider()

    /// A fixed reference design (not the user's pinned/random pick) so the
    /// preview always shows a consistent shape and only size changes.
    private static let previewAsset = WingAssets.pick(pinnedIndex: 0)
    private static let previewImage = NSImage(
        cgImage: previewAsset.image,
        size: NSSize(width: previewAsset.image.width, height: previewAsset.image.height)
    )
    private static let previewAspect = CGFloat(previewAsset.image.height) / CGFloat(previewAsset.image.width)

    init(currentIndex: Int, target: AnyObject, action: Selector) {
        super.init(frame: CGRect(x: 0, y: 0, width: 260, height: 50))
        label.frame = CGRect(x: 14, y: 29, width: 192, height: 16)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        addSubview(label)

        minimumImageView.image = Self.previewImage
        minimumImageView.imageScaling = .scaleProportionallyDown
        minimumImageView.frame = CGRect(x: 14, y: 7, width: 15, height: 13)
        addSubview(minimumImageView)

        slider.frame = CGRect(x: 35, y: 5, width: 158, height: 18)
        slider.minValue = 0
        slider.maxValue = Double(ButterflySize.widths.count - 1)
        slider.controlSize = .small
        slider.trackFillColor = .controlAccentColor
        slider.numberOfTickMarks = ButterflySize.widths.count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.target = target
        slider.action = action
        addSubview(slider)

        previewImageView.image = Self.previewImage
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(previewImageView)

        let clampedIndex = ButterflySize.widths.indices.contains(currentIndex) ? currentIndex : ButterflySize.defaultIndex
        slider.doubleValue = Double(clampedIndex)
        label.stringValue = "Size · \(ButterflySize.labels[clampedIndex])"
        updatePreview(forIndex: clampedIndex)
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    /// Called by the slider's action; returns the resulting index and
    /// updates the label and preview to match.
    func sliderMoved() -> Int {
        let index = Int(slider.doubleValue.rounded())
        label.stringValue = "Size · \(ButterflySize.labels[index])"
        updatePreview(forIndex: index)
        return index
    }

    private func updatePreview(forIndex index: Int) {
        let previewWidth: CGFloat = 14 + CGFloat(index) * 7 // 14...42pt across the 5 steps
        let previewHeight = previewWidth * Self.previewAspect
        previewImageView.frame = CGRect(
            x: bounds.width - 14 - previewWidth,
            y: 3 + (22 - previewHeight) / 2,
            width: previewWidth,
            height: previewHeight
        )
    }
}
