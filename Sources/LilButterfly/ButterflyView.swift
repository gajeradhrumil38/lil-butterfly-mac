import AppKit

final class ButterflyView: NSView {

    private let leftWing = CAShapeLayer()
    private let rightWing = CAShapeLayer()
    private let body = CAShapeLayer()

    static let size: CGFloat = 46

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildShapes()
        startFlutter()
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    private func buildShapes() {
        guard let root = layer else { return }
        let s = Self.size

        // Left wing (upper + lower lobe), roughly mirrored around x = 23.
        let leftPath = CGMutablePath()
        leftPath.move(to: CGPoint(x: 23, y: 26))
        leftPath.addCurve(to: CGPoint(x: 6, y: 24), control1: CGPoint(x: 10, y: 42), control2: CGPoint(x: -6, y: 38))
        leftPath.addCurve(to: CGPoint(x: 23, y: 26), control1: CGPoint(x: 10, y: 19), control2: CGPoint(x: 18, y: 21))
        leftPath.closeSubpath()
        leftPath.move(to: CGPoint(x: 23, y: 22))
        leftPath.addCurve(to: CGPoint(x: 9, y: 6), control1: CGPoint(x: 13, y: 16), control2: CGPoint(x: 2, y: 12))
        leftPath.addCurve(to: CGPoint(x: 23, y: 22), control1: CGPoint(x: 14, y: 2), control2: CGPoint(x: 20, y: 10))
        leftPath.closeSubpath()

        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: 23, y: 26))
        rightPath.addCurve(to: CGPoint(x: 40, y: 24), control1: CGPoint(x: 36, y: 42), control2: CGPoint(x: 52, y: 38))
        rightPath.addCurve(to: CGPoint(x: 23, y: 26), control1: CGPoint(x: 36, y: 19), control2: CGPoint(x: 28, y: 21))
        rightPath.closeSubpath()
        rightPath.move(to: CGPoint(x: 23, y: 22))
        rightPath.addCurve(to: CGPoint(x: 37, y: 6), control1: CGPoint(x: 33, y: 16), control2: CGPoint(x: 44, y: 12))
        rightPath.addCurve(to: CGPoint(x: 23, y: 22), control1: CGPoint(x: 32, y: 2), control2: CGPoint(x: 26, y: 10))
        rightPath.closeSubpath()

        leftWing.fillColor = NSColor(calibratedRed: 0.79, green: 0.65, blue: 0.91, alpha: 1).cgColor
        leftWing.anchorPoint = CGPoint(x: 23 / s, y: 23 / s)
        leftWing.position = CGPoint(x: 23, y: 23)
        leftWing.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        leftWing.path = leftPath

        rightWing.fillColor = NSColor(calibratedRed: 0.79, green: 0.65, blue: 0.91, alpha: 1).cgColor
        rightWing.anchorPoint = CGPoint(x: 23 / s, y: 23 / s)
        rightWing.position = CGPoint(x: 23, y: 23)
        rightWing.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        rightWing.path = rightPath

        let bodyPath = CGMutablePath()
        bodyPath.addEllipse(in: CGRect(x: 21, y: 12, width: 4, height: 20))
        bodyPath.addEllipse(in: CGRect(x: 20.5, y: 30, width: 5, height: 5))
        body.path = bodyPath
        body.fillColor = NSColor(calibratedRed: 0.29, green: 0.23, blue: 0.34, alpha: 1).cgColor

        root.addSublayer(leftWing)
        root.addSublayer(rightWing)
        root.addSublayer(body)

        // Soft drop shadow so it reads clearly over any background.
        root.shadowColor = NSColor.black.cgColor
        root.shadowOpacity = 0.18
        root.shadowRadius = 4
        root.shadowOffset = CGSize(width: 0, height: -2)
    }

    private func startFlutter() {
        let flutter = CABasicAnimation(keyPath: "transform.scale.x")
        flutter.fromValue = 1.0
        flutter.toValue = 0.55
        flutter.duration = 0.42
        flutter.autoreverses = true
        flutter.repeatCount = .infinity
        flutter.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        leftWing.add(flutter, forKey: "flutter")

        let flutterDelayed = flutter.copy() as! CABasicAnimation
        flutterDelayed.beginTime = CACurrentMediaTime() + 0.02
        rightWing.add(flutterDelayed, forKey: "flutter")
    }

    /// Moves the view's layer from `from` to `to` (in superlayer/window
    /// coordinates) with easing and a perpendicular "wobble" so the path
    /// feels alive rather than mechanical. Sets the final model position
    /// immediately so there's no snap-back when the animation is removed.
    func flyPath(from: CGPoint, to: CGPoint, duration: CFTimeInterval, easeIn: Bool, completion: (() -> Void)?) {
        guard let layer = layer else { return }

        let segments = 36
        let wobbleAmplitude: CGFloat = 22
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        let perp = length > 0 ? CGPoint(x: -dy / length, y: dx / length) : .zero

        let cgPath = CGMutablePath()
        cgPath.move(to: from)
        for i in 1...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let eased = easeIn ? (t * t * t) : (1 - pow(1 - t, 3))
            let baseX = from.x + dx * eased
            let baseY = from.y + dy * eased
            let wobble = sin(t * .pi * 3) * wobbleAmplitude * (1 - abs(2 * t - 1))
            cgPath.addLine(to: CGPoint(x: baseX + perp.x * wobble, y: baseY + perp.y * wobble))
        }

        layer.position = to // final model value, set up front

        let anim = CAKeyframeAnimation(keyPath: "position")
        anim.path = cgPath
        anim.duration = duration
        anim.calculationMode = .cubic
        anim.fillMode = .forwards
        layer.add(anim, forKey: "flight")

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion?()
        }
    }
}
