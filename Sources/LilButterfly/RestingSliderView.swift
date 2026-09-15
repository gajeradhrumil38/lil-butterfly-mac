import AppKit

/// A linear slider for how long the message card stays fully visible before
/// it starts fading out, hosted as an NSMenuItem's view the same way
/// IntervalSliderView/SizeSliderView are. Messages are short (a sentence or
/// two), so this uses a small, direct range rather than a log scale.
final class RestingSliderView: NSView {
    private let label = NSTextField(labelWithString: "")
    let slider = NSSlider()

    static let minSeconds: Double = 2
    static let maxSeconds: Double = 15

    init(currentSeconds: Double, target: AnyObject, action: Selector) {
        super.init(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        label.frame = CGRect(x: 14, y: 24, width: 192, height: 16)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        addSubview(label)

        slider.frame = CGRect(x: 14, y: 4, width: 192, height: 18)
        slider.minValue = Self.minSeconds
        slider.maxValue = Self.maxSeconds
        slider.isContinuous = true
        slider.target = target
        slider.action = action
        addSubview(slider)

        let clamped = min(max(currentSeconds, Self.minSeconds), Self.maxSeconds)
        slider.doubleValue = clamped
        label.stringValue = "Message stays for: \(Self.formatted(clamped))"
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    /// Called by the slider's action; returns the resulting seconds and
    /// updates the label to match.
    func sliderMoved() -> Double {
        let seconds = slider.doubleValue
        label.stringValue = "Message stays for: \(Self.formatted(seconds))"
        return seconds
    }

    static func formatted(_ seconds: Double) -> String {
        "\(Int(seconds.rounded()))s"
    }
}
