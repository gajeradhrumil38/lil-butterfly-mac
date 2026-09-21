import AppKit

/// The 4-5 sizes offered by the menu's size slider (Config.butterflySizeIndex
/// picks one). `defaultIndex` matches the original hardcoded 56pt so
/// existing configs and the Kavii reveal's own fixed 20pt stay unaffected.
enum ButterflySize {
    static let widths: [CGFloat] = [36, 46, 56, 70, 86]
    static let labels: [String] = ["Small", "Cozy", "Default", "Large", "Extra Large"]
    static let defaultIndex = 2

    static func width(forIndex index: Int) -> CGFloat {
        widths.indices.contains(index) ? widths[index] : widths[defaultIndex]
    }
}

final class ButterflyView: NSView {

    private let leftWing = CALayer()
    private let rightWing = CALayer()

    init(
        center: CGPoint,
        pinnedAssetIndex: Int?,
        displayWidth: CGFloat = ButterflySize.widths[ButterflySize.defaultIndex],
        edgeClipped: Bool = false
    ) {
        let asset = WingAssets.pick(pinnedIndex: pinnedAssetIndex)
        let image = asset.image
        let pointSize = CGSize(
            width: CGFloat(image.width) / WingAssets.rasterScale,
            height: CGFloat(image.height) / WingAssets.rasterScale
        )
        // Scale so the actual ink (wingspan), not the raw canvas width, ends
        // up at displayWidth — the 9 source SVGs don't all fill their
        // viewBox by the same margin, so scaling off the full canvas made
        // some designs look noticeably smaller than others at the same
        // nominal size.
        let inkWidthPoints = max(asset.inkBounds.width / WingAssets.rasterScale, 1)
        let scale = displayWidth / inkWidthPoints
        let displaySize = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)
        let frame = CGRect(
            x: center.x - displaySize.width / 2,
            y: center.y - displaySize.height / 2,
            width: displaySize.width,
            height: displaySize.height
        )
        super.init(frame: frame)
        wantsLayer = true
        buildWings(from: image, inkBounds: asset.inkBounds, displaySize: displaySize)
        startFlutter(edgeClipped: edgeClipped)
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    /// The view's center, in its superview's coordinate space. Every caller
    /// outside this file (ScreenOverlay, DockedOverlay, KaviiRevealOverlay)
    /// thinks in terms of centers, so this is the only thing they should
    /// read or write — never `layer.position` directly. A plain NSView's
    /// backing layer keeps anchorPoint at (0, 0), and confirmed by direct
    /// instrumentation, AppKit resyncs the layer from the view's own `frame`
    /// (which only `setFrameOrigin`/`.frame =` update) during normal
    /// display passes — so a raw `layer.position = someCenter` looks right
    /// immediately but silently reverts once that sync happens, which
    /// previously made the resting butterfly's model position snap back to
    /// its pre-flight spot (sometimes off-window entirely).
    var centerPosition: CGPoint {
        get { CGPoint(x: frame.midX, y: frame.midY) }
        set { setFrameOrigin(CGPoint(x: newValue.x - frame.width / 2, y: newValue.y - frame.height / 2)) }
    }

    private func buildWings(from image: CGImage, inkBounds: CGRect, displaySize: CGSize) {
        guard let root = layer else { return }

        let fullWidth = image.width
        let fullHeight = image.height
        // Split at the ink content's own midpoint rather than the raw
        // canvas midpoint, so the seam sits on the butterfly's actual body
        // line even if the source SVG's padding isn't perfectly symmetric.
        let splitX = min(max(Int(inkBounds.midX.rounded()), 1), fullWidth - 1)
        guard
            let leftCG = image.cropping(to: CGRect(x: 0, y: 0, width: splitX, height: fullHeight)),
            let rightCG = image.cropping(to: CGRect(x: splitX, y: 0, width: fullWidth - splitX, height: fullHeight))
        else { return }

        let leftWidth = displaySize.width * CGFloat(splitX) / CGFloat(fullWidth)
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

    /// A flat horizontal scale squish reads as the wing shrinking rather
    /// than folding, since there's no sense of it turning in space. Perspec-
    /// tive on the root layer plus a Y-axis rotation hinged at each wing's
    /// anchorPoint (already pinned to its body-side edge) makes the tip
    /// genuinely foreshorten toward/away from the viewer as it swings —
    /// much closer to a real wing flap for the same animation cost.
    ///
    /// `edgeClipped` softens both the perspective depth and the flap angle
    /// — when this view is centered on a screen edge for left/right
    /// docking, only one wing is ever actually on screen (the window's own
    /// bounds hard-clip the other half), and that lone wing's hinge sits
    /// right on the clip line. The full-strength foreshortening was tuned
    /// for two wings meeting symmetrically at that hinge; on just one, the
    /// same rotation swings its far edge sharply toward/away from the clip
    /// boundary, reading as an odd warp rather than a clean flap — a flat
    /// 2D silhouette wouldn't have this problem, only the 3D perspective
    /// does once it's cropped in half.
    private func startFlutter(edgeClipped: Bool = false) {
        var perspective = CATransform3DIdentity
        perspective.m34 = edgeClipped ? -1.0 / 1400 : -1.0 / 600
        layer?.sublayerTransform = perspective

        let flapAmplitude: CGFloat = edgeClipped ? 0.55 : 1.15 // radians; short of pi/2 so the wing never goes fully edge-on

        let flutter = CABasicAnimation(keyPath: "transform.rotation.y")
        flutter.fromValue = 0
        flutter.toValue = flapAmplitude
        flutter.duration = 0.42
        flutter.autoreverses = true
        flutter.repeatCount = .infinity
        flutter.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        leftWing.add(flutter, forKey: "flutter")

        // The two wings' anchorPoints are mirrored (each pinned to its own
        // body-side edge), so mirroring the rotation's sign too is what
        // keeps both tips foreshortening together instead of one swinging
        // toward the viewer while the other swings away.
        let flutterDelayed = flutter.copy() as! CABasicAnimation
        flutterDelayed.fromValue = 0
        flutterDelayed.toValue = -flapAmplitude
        flutterDelayed.beginTime = CACurrentMediaTime() + 0.02
        rightWing.add(flutterDelayed, forKey: "flutter")
    }

    /// Temporarily slows (rate < 1) or restores (rate = 1) the wing-flutter
    /// without restarting or jumping it — used by the Breathe-with-me
    /// check-in so the butterfly's own motion visibly settles in time with
    /// the breathing prompt, then speeds back up once it's done. Changing
    /// a layer's `speed` alone would jump the animation's phase at the
    /// moment of the change; capturing its current local time into
    /// `timeOffset` first (the standard CALayer pause/resume recipe,
    /// generalized to any rate rather than just 0) keeps it continuous.
    func setFlutterRate(_ rate: CGFloat) {
        for wing in [leftWing, rightWing] {
            let pausedTime = wing.convertTime(CACurrentMediaTime(), from: nil)
            wing.speed = Float(rate)
            wing.timeOffset = pausedTime
            wing.beginTime = CACurrentMediaTime()
        }
    }

    /// A small continuous hovering orbit while parked next to a message, so
    /// it reads as steadily still-flying in place rather than freezing —
    /// more like a real insect holding position than a subtle idle wobble.
    /// The orbit's keyframe path animates the *presentation* layer only
    /// (the model position, i.e. `centerPosition`/`frame`, never changes),
    /// so a subsequent flyPath reading `centerPosition` for its `from`
    /// point still gets the true rest point. Path coordinates are in the
    /// layer's own origin space (anchorPoint (0, 0)), so they're built
    /// relative to the current frame origin, not the center.
    func startHover() {
        guard let layer else { return }
        let origin = frame.origin
        let radiusX: CGFloat = 5
        let radiusY: CGFloat = 8
        let segments = 32
        let loopPath = CGMutablePath()
        loopPath.move(to: CGPoint(x: origin.x, y: origin.y + radiusY))
        for i in 1...segments {
            let angle = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
            loopPath.addLine(to: CGPoint(x: origin.x + sin(angle) * radiusX, y: origin.y + cos(angle) * radiusY))
        }
        loopPath.closeSubpath()

        let orbit = CAKeyframeAnimation(keyPath: "position")
        orbit.path = loopPath
        orbit.duration = 2.4
        orbit.calculationMode = .paced
        orbit.repeatCount = .infinity
        layer.add(orbit, forKey: "hoverOrbit")

        let sway = CABasicAnimation(keyPath: "transform.rotation.z")
        sway.fromValue = -0.06
        sway.toValue = 0.06
        sway.duration = 1.2
        sway.autoreverses = true
        sway.repeatCount = .infinity
        sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(sway, forKey: "hoverSway")
    }

    /// Stops the idle hover — call before starting a new flyPath, since
    /// flyPath's own tilt animation targets the same rotation.z component.
    func stopHover() {
        layer?.removeAnimation(forKey: "hoverOrbit")
        layer?.removeAnimation(forKey: "hoverSway")
    }

    /// Moves the view from `from` to `to` (both centers, in superview
    /// coordinates) with easing and a perpendicular "wobble" so the path
    /// feels alive rather than mechanical. Sets the final model position
    /// immediately (via `centerPosition`, not `layer.position` — see its
    /// doc comment) so there's no snap-back once the animation ends.
    func flyPath(from: CGPoint, to: CGPoint, duration: CFTimeInterval, easeIn: Bool, completion: (() -> Void)?) {
        guard let layer = layer else { return }

        // The keyframe animation drives the layer's raw `position`, which
        // is origin-space (anchorPoint (0, 0)), while `from`/`to`/the
        // wobble math below are all expressed as centers — so every point
        // in the path is offset by this constant to convert.
        let halfSize = CGPoint(x: frame.width / 2, y: frame.height / 2)

        let segments = 36
        let wobbleAmplitude: CGFloat = 22
        let tiltAmplitude: CGFloat = 0.2
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        let perp = length > 0 ? CGPoint(x: -dy / length, y: dx / length) : .zero

        let cgPath = CGMutablePath()
        cgPath.move(to: CGPoint(x: from.x - halfSize.x, y: from.y - halfSize.y))
        var rotations: [NSNumber] = [0]
        for i in 1...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let eased = easeIn ? (t * t * t) : (1 - pow(1 - t, 3))
            let baseX = from.x + dx * eased
            let baseY = from.y + dy * eased
            let envelope = 1 - abs(2 * t - 1)
            let phase = sin(t * .pi * 3)
            let wobble = phase * wobbleAmplitude * envelope
            let point = CGPoint(x: baseX + perp.x * wobble, y: baseY + perp.y * wobble)
            cgPath.addLine(to: CGPoint(x: point.x - halfSize.x, y: point.y - halfSize.y))
            rotations.append(NSNumber(value: Double(phase * tiltAmplitude * envelope)))
        }

        centerPosition = to // final model value, set up front via the view's own frame API
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
