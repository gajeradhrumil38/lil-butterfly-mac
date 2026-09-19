import AppKit

/// A short, intentional celebration: butterflies arrange themselves into the
/// word "Kavii" instead of drawing the name as a normal text layer. Each
/// time it runs, one of several distinct entrance styles is picked at
/// random, so it doesn't play out identically every time.
final class KaviiRevealOverlay {
    private let window: OverlayWindow
    private let screenFrame: CGRect
    private var butterflies: [ButterflyView] = []
    private var isBusy = false

    /// Distinct ways the word can assemble, inspired by common particle-text
    /// reveal patterns (converge/burst/sweep/scatter): a single fixed motion
    /// reads as mechanical on repeat plays, so each run looks different.
    private enum RevealStyle: CaseIterable, Equatable {
        /// Each butterfly flies in from its own random point along the
        /// screen border — the original behavior.
        case borderScatter
        /// All butterflies emerge from one point at the top-center (as if
        /// from behind the menu bar), first to a loose cloud near the word,
        /// pause, then snap together into exact formation — a small swarm
        /// that resolves into text rather than arriving pre-aimed.
        case topBurst
        /// Every butterfly enters from the same edge, but staggered by its
        /// target's position along that edge instead of by index, so the
        /// word visibly builds in reading order (left-to-right or
        /// top-to-bottom) rather than scattering in all at once.
        case sideSweep
        /// Each butterfly enters from whichever of the four screen corners
        /// is nearest its own target, well past the corner diagonally — the
        /// word is visibly pulled together from all four corners of the
        /// screen at once, rather than from one edge.
        case cornerConverge
        /// Alternates each row's entrance between the far left and far
        /// right edges (by index parity), aimed at its own row's height —
        /// reads as a "zipper" closing into the word from both sides.
        case alternatingSweep
    }

    init(screen: NSScreen) {
        window = OverlayWindow(screen: screen)
        screenFrame = CGRect(origin: .zero, size: screen.frame.size)
    }

    func show() {
        guard !isBusy, let host = window.contentView else { return }
        isBusy = true

        let center = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
        let targets = wordmarkTargets(around: center)
        let assetCount = max(1, WingAssets.names().count)
        let style = RevealStyle.allCases.randomElement()!

        let wordBounds = boundingBox(of: targets)
        let cloudCenter = CGPoint(x: wordBounds.midX, y: wordBounds.midY)
        let sweepEdge = ScreenEdge.allCases.randomElement()!

        for (index, target) in targets.enumerated() {
            let (start, flightDuration, delay): (CGPoint, TimeInterval, TimeInterval)
            switch style {
            case .borderScatter:
                let edge = ScreenEdge.allCases.randomElement()!
                let borderPoint = edge.restPoint(in: screenFrame, margin: 0)
                start = edge.offscreenPoint(in: screenFrame, restX: borderPoint.x, restY: borderPoint.y, margin: 0)
                flightDuration = 1.0
                delay = Double(index) * 0.04

            case .topBurst:
                // Spread across a wide arc and well above the screen
                // (rather than one funnel point just past the edge) so
                // the whole group visibly arrives from outside, not from
                // a single spot barely off-screen.
                start = CGPoint(x: screenFrame.midX + CGFloat.random(in: -160...160), y: screenFrame.height + 140)
                flightDuration = 0.75
                delay = Double(index) * 0.02

            case .sideSweep:
                let alongEdgeFraction: CGFloat
                switch sweepEdge {
                case .left, .right: alongEdgeFraction = (target.y - wordBounds.minY) / max(wordBounds.height, 1)
                case .top, .bottom: alongEdgeFraction = (target.x - wordBounds.minX) / max(wordBounds.width, 1)
                }
                let edgePoint = sweepEdge.restPoint(in: screenFrame, margin: 0)
                start = sweepEdge.offscreenPoint(in: screenFrame, restX: edgePoint.x, restY: edgePoint.y, margin: 0)
                flightDuration = 0.9
                delay = Double(alongEdgeFraction) * 1.1

            case .cornerConverge:
                let fromLeft = target.x < wordBounds.midX
                let fromBottom = target.y < wordBounds.midY
                start = CGPoint(
                    x: fromLeft ? -70 : screenFrame.width + 70,
                    y: fromBottom ? -70 : screenFrame.height + 70
                )
                flightDuration = 1.1
                delay = Double(index) * 0.02

            case .alternatingSweep:
                let edge: ScreenEdge = index % 2 == 0 ? .left : .right
                start = edge.offscreenPoint(in: screenFrame, restX: 0, restY: target.y, margin: 0)
                flightDuration = 0.85
                delay = Double(index) * 0.03
            }

            let butterfly = ButterflyView(center: start, pinnedAssetIndex: Int.random(in: 0..<assetCount), displayWidth: 20)
            butterfly.alphaValue = 0
            host.addSubview(butterfly)
            butterflies.append(butterfly)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.isBusy else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    butterfly.animator().alphaValue = 1
                }
                if style == .topBurst {
                    // Phase 1: burst out to a loose point near the word.
                    let cloudSpread: CGFloat = 90
                    let cloudPoint = CGPoint(x: cloudCenter.x + CGFloat.random(in: -cloudSpread...cloudSpread),
                                             y: cloudCenter.y + CGFloat.random(in: -cloudSpread...cloudSpread))
                    butterfly.flyPath(from: start, to: cloudPoint, duration: flightDuration, easeIn: false) {
                        guard self.isBusy else { return }
                        // Phase 2: settle into exact formation.
                        butterfly.flyPath(from: cloudPoint, to: target, duration: 0.55, easeIn: false) {
                            guard self.isBusy else { return }
                            butterfly.startHover()
                        }
                    }
                } else {
                    butterfly.flyPath(from: start, to: target, duration: flightDuration, easeIn: false) {
                        guard self.isBusy else { return }
                        butterfly.startHover()
                    }
                }
            }
        }

        let holdSeconds = 4.6
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) {
            guard self.isBusy else { return }
            self.departWordmark()
        }
    }

    /// The reverse of assembling: rather than fading the whole word out in
    /// place, every butterfly peels off and flies back out past a random
    /// screen edge, the same way the borderScatter entrance style brings
    /// them in — just outbound instead of inbound, and staggered per
    /// butterfly instead of all at once, so the word visibly scatters apart
    /// rather than vanishing.
    private func departWordmark() {
        let departing = butterflies
        butterflies.removeAll()
        guard !departing.isEmpty else {
            isBusy = false
            return
        }

        var remaining = departing.count
        for (index, butterfly) in departing.enumerated() {
            butterfly.stopHover()
            let edge = ScreenEdge.allCases.randomElement()!
            let edgePoint = edge.restPoint(in: screenFrame, margin: 0)
            let off = edge.offscreenPoint(in: screenFrame, restX: edgePoint.x, restY: edgePoint.y, margin: 0)
            let delay = Double(index) * 0.02 + Double.random(in: 0...0.2)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                butterfly.flyPath(from: butterfly.centerPosition, to: off, duration: 0.9, easeIn: true) {
                    butterfly.removeFromSuperview()
                    remaining -= 1
                    if remaining == 0 {
                        self.isBusy = false
                    }
                }
            }
        }
    }

    private func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func wordmarkTargets(around center: CGPoint) -> [CGPoint] {
        // A compact 5x7 bitmap font. Each filled cell becomes one butterfly,
        // so the name is literally assembled from the wing artwork.
        let letters = [
            ["10001", "10010", "10100", "11000", "10100", "10010", "10001"], // K
            ["00000", "00000", "01110", "00001", "01111", "10001", "01111"], // a
            ["00000", "00000", "10001", "10001", "10001", "01010", "00100"], // v
            ["00100", "00000", "01100", "00100", "00100", "00100", "01110"], // i
            ["00100", "00000", "01100", "00100", "00100", "00100", "01110"], // i
        ]
        let cell: CGFloat = 20
        let letterGap = 2
        let totalColumns = letters.reduce(0) { total, letter in
            total + letter[0].count
        } + letterGap * (letters.count - 1)
        let startX = center.x - CGFloat(totalColumns) * cell / 2 + cell / 2
        let startY = center.y + CGFloat(letters[0].count - 1) * cell / 2

        var points: [CGPoint] = []
        var columnOffset = 0
        for letter in letters {
            for (row, pattern) in letter.enumerated() {
                for (column, value) in pattern.enumerated() where value == "1" {
                    points.append(CGPoint(
                        x: startX + CGFloat(columnOffset + column) * cell,
                        y: startY - CGFloat(row) * cell
                    ))
                }
            }
            columnOffset += letter[0].count + letterGap
        }
        return points
    }
}
