import AppKit

/// Small animated illustrations that sit beside a message. Drawn from
/// vector paths — the same thing an SVG is — but as separate Core
/// Animation layers rather than one flattened image, because a loaded
/// SVG can't animate its parts: the eyelids, the water line, the falling
/// drop each need to be their own layer to move on their own.
///
/// Motion follows a few rules so these stay cute rather than busy:
/// spring in once on arrival, then slow idle loops (seconds, not
/// fractions of a second), small amplitudes, and nothing that flashes.
enum IllustrationKind {
    case eyes
    /// Eyes whose pupils drift up and away — for the 20-20-20 break,
    /// literally "looking at something far off".
    case eyesLookingFar
    case water
    case moon
    case heart

    /// Picks an illustration for a plain message from its wording.
    /// Check-in cards decide for themselves (most already animate in
    /// their own strip), except the 20-20-20 reset, which gets eyes
    /// looking into the distance next to its countdown.
    static func resolve(message: String, checkInStyle: CheckInStyle?) -> IllustrationKind? {
        if let checkInStyle {
            return checkInStyle == .eyeRestReset ? .eyesLookingFar : nil
        }
        let text = message.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        if has(["water", "sip", "💧", "hydrat", "drink"]) { return .water }
        if has(["eye", "blink", "screen", "look away", "far away", "across the room", "20-20-20", "20 feet"]) { return .eyes }
        if has(["sleep", "nap", "💤", "bed", "dream", "night", "close your eyes"]) { return .moon }
        if has(["proud", "doing so well", "deserve", "love", "💛", "care", "you've got this", "glad"]) { return .heart }
        return nil
    }
}

final class IllustrationView: NSView {
    let kind: IllustrationKind
    /// Our own container (anchor at center, unlike an NSView's backing
    /// layer), so the entrance can scale and tilt around the middle.
    private let root = CALayer()
    private var eyeLayers: [CALayer] = []

    init(kind: IllustrationKind, size: CGSize = CGSize(width: 30, height: 30)) {
        self.kind = kind
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        root.frame = bounds
        root.opacity = 0 // revealed by playEntrance()
        layer?.addSublayer(root)
        switch kind {
        case .eyes: buildEyes(lookingFar: false)
        case .eyesLookingFar: buildEyes(lookingFar: true)
        case .water: buildWater()
        case .moon: buildMoon()
        case .heart: buildHeart()
        }
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    /// Springs in from small with a slight tilt, like it just landed.
    func playEntrance(delay: TimeInterval = 0) {
        let start = CACurrentMediaTime() + delay
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.2
        fade.beginTime = start
        fade.fillMode = .backwards
        root.add(fade, forKey: "entranceFade")

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.3
        pop.toValue = 1
        pop.damping = 9
        pop.stiffness = 180
        pop.mass = 0.6
        pop.duration = pop.settlingDuration
        pop.beginTime = start
        pop.fillMode = .backwards
        root.add(pop, forKey: "entrancePop")

        let tilt = CASpringAnimation(keyPath: "transform.rotation.z")
        tilt.fromValue = -0.3
        tilt.toValue = 0
        tilt.damping = 8
        tilt.stiffness = 160
        tilt.duration = tilt.settlingDuration
        tilt.beginTime = start
        tilt.fillMode = .backwards
        root.add(tilt, forKey: "entranceTilt")
        root.opacity = 1
    }

    // MARK: - Eyes

    private func buildEyes(lookingFar: Bool) {
        let w = bounds.width, h = bounds.height
        let eyeW = h * 0.44, eyeH = h * 0.56
        for cx in [w / 2 - eyeW * 0.62, w / 2 + eyeW * 0.62] {
            let eye = CALayer()
            eye.frame = CGRect(x: cx - eyeW / 2, y: h / 2 - eyeH / 2, width: eyeW, height: eyeH)
            let white = CAShapeLayer()
            white.path = CGPath(ellipseIn: eye.bounds, transform: nil)
            white.fillColor = NSColor.white.withAlphaComponent(0.95).cgColor
            eye.addSublayer(white)

            // Pupil + highlight live in a per-eye layer that the shared
            // pupil animation moves, clipped to the eye's own white.
            let mask = CAShapeLayer()
            mask.frame = eye.bounds
            mask.path = white.path
            let iris = CALayer()
            iris.frame = eye.bounds
            iris.mask = mask
            let r = eyeW * 0.3
            let pupil = CAShapeLayer()
            pupil.path = CGPath(ellipseIn: CGRect(x: eyeW / 2 - r, y: eyeH / 2 - r - 1, width: r * 2, height: r * 2), transform: nil)
            pupil.fillColor = NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.22, alpha: 1).cgColor
            let shine = CAShapeLayer()
            shine.path = CGPath(ellipseIn: CGRect(x: eyeW / 2 - r * 0.45, y: eyeH / 2 + r * 0.05, width: r * 0.6, height: r * 0.6), transform: nil)
            shine.fillColor = NSColor.white.cgColor
            let look = CALayer()
            look.frame = eye.bounds
            look.addSublayer(pupil)
            look.addSublayer(shine)
            iris.addSublayer(look)
            eye.addSublayer(iris)
            root.addSublayer(eye)
            eyeLayers.append(eye)

            let glance = CAKeyframeAnimation(keyPath: "position")
            let c = CGPoint(x: look.position.x, y: look.position.y)
            if lookingFar {
                // Up and away, then a slow drift — gazing at the horizon.
                glance.values = [c, CGPoint(x: c.x + 2.2, y: c.y + 2.6), CGPoint(x: c.x + 1.2, y: c.y + 2.8), CGPoint(x: c.x + 2.2, y: c.y + 2.6)].map { NSValue(point: $0) }
                glance.keyTimes = [0, 0.15, 0.6, 1]
                glance.duration = 5
            } else {
                glance.values = [c, c, CGPoint(x: c.x - 2, y: c.y), CGPoint(x: c.x - 2, y: c.y), CGPoint(x: c.x + 2, y: c.y), CGPoint(x: c.x + 2, y: c.y), c].map { NSValue(point: $0) }
                glance.keyTimes = [0, 0.2, 0.3, 0.5, 0.6, 0.85, 1]
                glance.duration = 6
            }
            glance.calculationMode = .cubic
            glance.repeatCount = .infinity
            look.add(glance, forKey: "glance")
        }
        startIdleBlink()
    }

    private func startIdleBlink() {
        for eye in eyeLayers {
            let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
            blink.values = [1, 1, 0.08, 1, 1]
            blink.keyTimes = [0, 0.86, 0.9, 0.95, 1]
            blink.duration = 3.4
            blink.repeatCount = .infinity
            eye.add(blink, forKey: "idleBlink")
        }
    }

    /// Slow, deliberate blinks for Blink Break — paced to be followed,
    /// replacing the idle blink while it runs.
    func blink(times: Int, completion: @escaping () -> Void) {
        eyeLayers.forEach { $0.removeAnimation(forKey: "idleBlink") }
        var remaining = times
        func once() {
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                remaining -= 1
                if remaining > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { once() }
                } else {
                    completion()
                }
            }
            for eye in eyeLayers {
                let close = CAKeyframeAnimation(keyPath: "transform.scale.y")
                close.values = [1, 0.06, 0.06, 1]
                close.keyTimes = [0, 0.35, 0.55, 1]
                close.timingFunctions = [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
                close.duration = 0.55
                eye.add(close, forKey: "blink")
            }
            CATransaction.commit()
        }
        once()
    }

    // MARK: - Water

    private func buildWater() {
        // A glass, open at the top, narrower at the base.
        let top: CGFloat = 26, bottom: CGFloat = 3
        let glassPath = CGMutablePath()
        glassPath.move(to: CGPoint(x: 5, y: top))
        glassPath.addLine(to: CGPoint(x: 8, y: bottom))
        glassPath.addLine(to: CGPoint(x: 22, y: bottom))
        glassPath.addLine(to: CGPoint(x: 25, y: top))

        let interior = CGMutablePath()
        interior.move(to: CGPoint(x: 6.2, y: top))
        interior.addLine(to: CGPoint(x: 8.9, y: bottom + 1))
        interior.addLine(to: CGPoint(x: 21.1, y: bottom + 1))
        interior.addLine(to: CGPoint(x: 23.8, y: top))
        interior.closeSubpath()

        let liquid = CALayer()
        liquid.frame = bounds
        let liquidMask = CAShapeLayer()
        liquidMask.frame = liquid.bounds
        liquidMask.path = interior
        liquid.mask = liquidMask
        root.addSublayer(liquid)

        // A wave two wavelengths wide, sliding one wavelength per loop,
        // so the surface sloshes continuously with no visible seam.
        let wavelength: CGFloat = 12, level: CGFloat = 15, amp: CGFloat = 1.3
        let wavePath = CGMutablePath()
        wavePath.move(to: CGPoint(x: 0, y: 0))
        var x: CGFloat = 0
        wavePath.addLine(to: CGPoint(x: 0, y: level))
        while x < 30 + wavelength * 2 {
            wavePath.addQuadCurve(to: CGPoint(x: x + wavelength / 2, y: level), control: CGPoint(x: x + wavelength / 4, y: level + amp))
            wavePath.addQuadCurve(to: CGPoint(x: x + wavelength, y: level), control: CGPoint(x: x + wavelength * 3 / 4, y: level - amp))
            x += wavelength
        }
        wavePath.addLine(to: CGPoint(x: x, y: 0))
        wavePath.closeSubpath()
        let wave = CAShapeLayer()
        wave.path = wavePath
        wave.fillColor = NSColor(calibratedRed: 0.35, green: 0.68, blue: 1.0, alpha: 0.9).cgColor
        wave.frame = CGRect(x: -wavelength, y: 0, width: x, height: 30)
        liquid.addSublayer(wave)
        let slosh = CABasicAnimation(keyPath: "position.x")
        slosh.byValue = wavelength
        slosh.duration = 1.6
        slosh.repeatCount = .infinity
        wave.add(slosh, forKey: "slosh")
        let bob = CABasicAnimation(keyPath: "position.y")
        bob.byValue = 0.8
        bob.duration = 2.2
        bob.autoreverses = true
        bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        wave.add(bob, forKey: "bob")

        // Two tiny bubbles drifting up through the water.
        for (i, bx) in [12.0, 17.5].enumerated() {
            let bubble = CAShapeLayer()
            bubble.path = CGPath(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2), transform: nil)
            bubble.fillColor = NSColor.white.withAlphaComponent(0.75).cgColor
            bubble.position = CGPoint(x: bx, y: 5)
            liquid.addSublayer(bubble)
            let rise = CAKeyframeAnimation(keyPath: "position.y")
            rise.values = [5, 14]
            rise.duration = 1.9
            rise.beginTime = CACurrentMediaTime() + Double(i) * 0.95
            rise.repeatCount = .infinity
            bubble.add(rise, forKey: "rise")
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0]
            fade.keyTimes = [0, 0.3, 1]
            fade.duration = 1.9
            fade.beginTime = rise.beginTime
            fade.repeatCount = .infinity
            bubble.add(fade, forKey: "fade")
        }

        let glass = CAShapeLayer()
        glass.path = glassPath
        glass.fillColor = nil
        glass.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        glass.lineWidth = 1.6
        glass.lineJoin = .round
        glass.lineCap = .round
        root.addSublayer(glass)

        // A drop that falls in every few seconds.
        let drop = CAShapeLayer()
        let d = CGMutablePath()
        d.move(to: CGPoint(x: 0, y: 3.2))
        d.addQuadCurve(to: CGPoint(x: -1.8, y: -0.4), control: CGPoint(x: -1.8, y: 1.2))
        d.addArc(center: CGPoint(x: 0, y: -0.4), radius: 1.8, startAngle: .pi, endAngle: 0, clockwise: false)
        d.addQuadCurve(to: CGPoint(x: 0, y: 3.2), control: CGPoint(x: 1.8, y: 1.2))
        drop.path = d
        drop.fillColor = NSColor(calibratedRed: 0.55, green: 0.8, blue: 1.0, alpha: 1).cgColor
        drop.position = CGPoint(x: 15, y: 29)
        drop.opacity = 0
        root.addSublayer(drop)
        let fall = CAKeyframeAnimation(keyPath: "position.y")
        fall.values = [29, 29, 16, 16]
        fall.keyTimes = [0, 0.55, 0.78, 1]
        fall.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .linear)]
        fall.duration = 3.2
        fall.repeatCount = .infinity
        drop.add(fall, forKey: "fall")
        let show = CAKeyframeAnimation(keyPath: "opacity")
        show.values = [0, 0, 1, 1, 0, 0]
        show.keyTimes = [0, 0.45, 0.55, 0.74, 0.8, 1]
        show.duration = 3.2
        show.repeatCount = .infinity
        drop.add(show, forKey: "show")
    }

    // MARK: - Moon

    private func buildMoon() {
        let moonBox = CALayer()
        moonBox.frame = CGRect(x: 1, y: 2, width: 22, height: 22)
        let disc = CAShapeLayer()
        disc.frame = moonBox.bounds
        disc.path = CGPath(ellipseIn: moonBox.bounds.insetBy(dx: 1, dy: 1), transform: nil)
        disc.fillColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.45, alpha: 1).cgColor
        // Carve the crescent: everything except an offset circle.
        let carve = CAShapeLayer()
        carve.frame = disc.bounds
        let carvePath = CGMutablePath()
        carvePath.addRect(moonBox.bounds.insetBy(dx: -4, dy: -4))
        carvePath.addEllipse(in: CGRect(x: 7, y: 6, width: 17, height: 17))
        carve.path = carvePath
        carve.fillRule = .evenOdd
        disc.mask = carve
        moonBox.addSublayer(disc)
        root.addSublayer(moonBox)
        let rock = CABasicAnimation(keyPath: "transform.rotation.z")
        rock.fromValue = -0.14
        rock.toValue = 0.14
        rock.duration = 2.6
        rock.autoreverses = true
        rock.repeatCount = .infinity
        rock.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        moonBox.add(rock, forKey: "rock")

        for (i, size) in [7.0, 8.5, 10.0].enumerated() {
            let z = CATextLayer()
            z.string = "z"
            z.font = NSFont.systemFont(ofSize: size, weight: .heavy)
            z.fontSize = size
            z.foregroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
            z.contentsScale = 2
            z.alignmentMode = .center
            z.frame = CGRect(x: 18, y: 12, width: 10, height: 12)
            z.opacity = 0
            root.addSublayer(z)
            let start = CACurrentMediaTime() + Double(i) * 0.9
            let float = CAKeyframeAnimation(keyPath: "position")
            float.values = [CGPoint(x: 21, y: 16), CGPoint(x: 25, y: 22), CGPoint(x: 23, y: 29)].map { NSValue(point: $0) }
            float.duration = 2.7
            float.beginTime = start
            float.repeatCount = .infinity
            z.add(float, forKey: "float")
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0]
            fade.keyTimes = [0, 0.3, 1]
            fade.duration = 2.7
            fade.beginTime = start
            fade.repeatCount = .infinity
            z.add(fade, forKey: "fade")
        }
    }

    // MARK: - Heart

    private func buildHeart() {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 15, y: 5))
        p.addCurve(to: CGPoint(x: 4, y: 18), control1: CGPoint(x: 10, y: 9), control2: CGPoint(x: 4, y: 13))
        p.addCurve(to: CGPoint(x: 15, y: 22), control1: CGPoint(x: 4, y: 26), control2: CGPoint(x: 12, y: 27))
        p.addCurve(to: CGPoint(x: 26, y: 18), control1: CGPoint(x: 18, y: 27), control2: CGPoint(x: 26, y: 26))
        p.addCurve(to: CGPoint(x: 15, y: 5), control1: CGPoint(x: 26, y: 13), control2: CGPoint(x: 20, y: 9))
        p.closeSubpath()
        let heart = CAShapeLayer()
        heart.frame = bounds
        heart.path = p
        heart.fillColor = NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.6, alpha: 0.95).cgColor
        root.addSublayer(heart)
        let beat = CAKeyframeAnimation(keyPath: "transform.scale")
        beat.values = [1, 1.13, 1, 1.09, 1, 1]
        beat.keyTimes = [0, 0.1, 0.2, 0.3, 0.42, 1]
        beat.duration = 1.9
        beat.repeatCount = .infinity
        heart.add(beat, forKey: "beat")
    }
}
