import AppKit

final class IntervalSliderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let fastIcon = NSImageView()
    private let slowIcon = NSImageView()
    let slider = NSSlider()
    static let minSeconds: Double = 10
    static let maxSeconds: Double = 3 * 60 * 60

    init(currentSeconds: Double, target: AnyObject, action: Selector) {
        super.init(frame: CGRect(x: 0, y: 0, width: 250, height: 50))
        label.frame = CGRect(x: 14, y: 29, width: 222, height: 16)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        addSubview(label)

        configure(icon: fastIcon, symbol: "hare", frame: CGRect(x: 14, y: 6, width: 16, height: 16))
        configure(icon: slowIcon, symbol: "tortoise", frame: CGRect(x: 220, y: 6, width: 16, height: 16))

        slider.frame = CGRect(x: 36, y: 5, width: 178, height: 18)
        slider.minValue = 0
        slider.maxValue = 1
        slider.controlSize = .small
        slider.trackFillColor = .controlAccentColor
        if #available(macOS 26.0, *) {
            slider.tintProminence = .primary
        }
        slider.isContinuous = true
        slider.target = target
        slider.action = action
        addSubview(slider)
        slider.doubleValue = Self.sliderValue(forSeconds: currentSeconds)
        label.stringValue = "Every · \(Self.formatted(currentSeconds))"
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    static func seconds(forSliderValue value: Double) -> Double {
        minSeconds * pow(maxSeconds / minSeconds, value)
    }

    static func sliderValue(forSeconds seconds: Double) -> Double {
        let clamped = min(max(seconds, minSeconds), maxSeconds)
        return log(clamped / minSeconds) / log(maxSeconds / minSeconds)
    }

    func sliderMoved() -> Double {
        let seconds = Self.seconds(forSliderValue: slider.doubleValue)
        label.stringValue = "Every · \(Self.formatted(seconds))"
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
        if seconds < 60 { return "\(Int(seconds))s" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
