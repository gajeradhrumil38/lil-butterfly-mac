import AppKit

/// A discrete, tick-stopped slider for picking one of ButterflySize.widths,
/// hosted as an NSMenuItem's view the same way IntervalSliderView is.
final class SizeSliderView: NSView {
    private let label = NSTextField(labelWithString: "")
    let slider = NSSlider()

    init(currentIndex: Int, target: AnyObject, action: Selector) {
        super.init(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        label.frame = CGRect(x: 14, y: 24, width: 192, height: 16)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        addSubview(label)

        slider.frame = CGRect(x: 14, y: 4, width: 192, height: 18)
        slider.minValue = 0
        slider.maxValue = Double(ButterflySize.widths.count - 1)
        slider.numberOfTickMarks = ButterflySize.widths.count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.target = target
        slider.action = action
        addSubview(slider)

        let clampedIndex = ButterflySize.widths.indices.contains(currentIndex) ? currentIndex : ButterflySize.defaultIndex
        slider.doubleValue = Double(clampedIndex)
        label.stringValue = "Butterfly size: \(ButterflySize.labels[clampedIndex])"
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    /// Called by the slider's action; returns the resulting index and
    /// updates the label to match.
    func sliderMoved() -> Int {
        let index = Int(slider.doubleValue.rounded())
        label.stringValue = "Butterfly size: \(ButterflySize.labels[index])"
        return index
    }
}
