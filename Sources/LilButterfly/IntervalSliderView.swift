import AppKit

final class IntervalSliderView: NSView {
    private let label = NSTextField(labelWithString: "")
    let slider = NSSlider()
    static let minSeconds: Double = 10
    static let maxSeconds: Double = 3 * 60 * 60

    init(currentSeconds: Double, target: AnyObject, action: Selector) {
        super.init(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        label.frame = CGRect(x: 14, y: 24, width: 192, height: 16)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        addSubview(label)
        slider.frame = CGRect(x: 14, y: 4, width: 192, height: 18)
        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.target = target
        slider.action = action
        addSubview(slider)
        slider.doubleValue = Self.sliderValue(forSeconds: currentSeconds)
        label.stringValue = "Interval: \(Self.formatted(currentSeconds))"
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
        label.stringValue = "Interval: \(Self.formatted(seconds))"
        return seconds
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
