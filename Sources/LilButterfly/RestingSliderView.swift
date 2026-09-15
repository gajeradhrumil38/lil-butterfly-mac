import AppKit

/// A linear slider for how long the message card stays fully visible before
/// it starts fading out, hosted as an NSMenuItem's view the same way
/// IntervalSliderView/SizeSliderView are. Messages are short (a sentence or
/// two), so this uses a small, direct range rather than a log scale.
final class RestingSliderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let shortIcon = NSImageView()
    private let longIcon = NSImageView()
    let slider = NSSlider()

    static let minSeconds: Double = 2
    static let maxSeconds: Double = 15

    init(currentSeconds: Double, target: AnyObject, action: Selector) {
        super.init(frame: CGRect(x: 0, y: 0, width: 250, height: 50))
        label.frame = CGRect(x: 14, y: 29, width: 222, height: 16)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        addSubview(label)

        configure(icon: shortIcon, symbol: "text.bubble", frame: CGRect(x: 14, y: 6, width: 16, height: 16))
        configure(icon: longIcon, symbol: "hourglass", frame: CGRect(x: 220, y: 6, width: 16, height: 16))

        slider.frame = CGRect(x: 36, y: 5, width: 178, height: 18)
        slider.minValue = Self.minSeconds
        slider.maxValue = Self.maxSeconds
        slider.isContinuous = true
        slider.target = target
        slider.action = action
        addSubview(slider)

        let clamped = min(max(currentSeconds, Self.minSeconds), Self.maxSeconds)
        slider.doubleValue = clamped
        label.stringValue = "Visible · \(Self.formatted(clamped))"
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    /// Called by the slider's action; returns the resulting seconds and
    /// updates the label to match.
    func sliderMoved() -> Double {
        let seconds = slider.doubleValue
        label.stringValue = "Visible · \(Self.formatted(seconds))"
        return seconds
    }

    private func configure(icon: NSImageView, symbol: String, frame: CGRect) {
        icon.frame = frame
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        addSubview(icon)
    }

    static func formatted(_ seconds: Double) -> String {
        "\(Int(seconds.rounded()))s"
    }
}
