import AppKit

final class ButterflyView: NSView {

    private let leftWing = CALayer()
    private let rightWing = CALayer()

    init(center: CGPoint, pinnedAssetIndex: Int?, displayWidth: CGFloat = 56) {
        let image = WingAssets.pick(pinnedIndex: pinnedAssetIndex)
        let pointSize = CGSize(
            width: CGFloat(image.width) / WingAssets.rasterScale,
            height: CGFloat(image.height) / WingAssets.rasterScale
        )
        let scale = displayWidth / pointSize.width
        let displaySize = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)
        let frame = CGRect(
            x: center.x - displaySize.width / 2,
            y: center.y - displaySize.height / 2,
            width: displaySize.width,
            height: displaySize.height
        )
        super.init(frame: frame)
        wantsLayer = true
        buildWings(from: image, displaySize: displaySize)
        startFlutter()
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    private func buildWings(from image: CGImage, displaySize: CGSize) {
        guard let root = layer else { return }

        let fullWidth = image.width
        let fullHeight = image.height
        let leftHalfPixels = fullWidth / 2
        guard
            let leftCG = image.cropping(to: CGRect(x: 0, y: 0, width: leftHalfPixels, height: fullHeight)),
            let rightCG = image.cropping(to: CGRect(x: leftHalfPixels, y: 0, width: fullWidth - leftHalfPixels, height: fullHeight))
        else { return }

        let leftWidth = displaySize.width * CGFloat(leftHalfPixels) / CGFloat(fullWidth)
        let rightWidth = displaySize.width - leftWidth

        leftWing.contents = leftCG
        leftWing.contentsScale = WingAssets.rasterScale
        leftWing.bounds = CGRect(x: 0, y: 0, width: leftWidth, height: displaySize.height)
        leftWing.anchorPoint = CGPoint(x: 1, y: 0.5)
        leftWing.position = CGPoint(x: displaySize.width / 2, y: displaySize.height / 2)

        rightWing.contents = rightCG
        rightWing.contentsScale = WingAssets.rasterScale
        rightWing.bounds = CGRect(x: 0, y: 0, width: rightWidth, height: displaySize.height)
        rightWing.anchorPoint = CGPoint(x: 0, y: 0.5)
        rightWing.position = CGPoint(x: displaySize.width / 2, y: displaySize.height / 2)

        root.addSublayer(leftWing)
        root.addSublayer(rightWing)

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
        let tiltAmplitude: CGFloat = 0.2
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        let perp = length > 0 ? CGPoint(x: -dy / length, y: dx / length) : .zero

        let cgPath = CGMutablePath()
        cgPath.move(to: from)
        var rotations: [NSNumber] = [0]
        for i in 1...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let eased = easeIn ? (t * t * t) : (1 - pow(1 - t, 3))
            let baseX = from.x + dx * eased
            let baseY = from.y + dy * eased
            let envelope = 1 - abs(2 * t - 1)
            let phase = sin(t * .pi * 3)
            let wobble = phase * wobbleAmplitude * envelope
            cgPath.addLine(to: CGPoint(x: baseX + perp.x * wobble, y: baseY + perp.y * wobble))
            rotations.append(NSNumber(value: Double(phase * tiltAmplitude * envelope)))
        }

        layer.position = to
        layer.transform = CATransform3DIdentity

        let anim = CAKeyframeAnimation(keyPath: "position")
        anim.path = cgPath
        anim.duration = duration
        anim.calculationMode = .cubic
        anim.fillMode = .forwards
        layer.add(anim, forKey: "flight")

        let tilt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        tilt.values = rotations
        tilt.duration = duration
        tilt.calculationMode = .cubic
        tilt.fillMode = .forwards
        layer.add(tilt, forKey: "tilt")

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion?()
        }
    }
}
