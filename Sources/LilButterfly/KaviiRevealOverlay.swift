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
        /// Butterflies start almost exactly where they'll land and drift
        /// the last short distance into place — reads as materializing
        /// rather than arriving from far away.
        case converge
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
                start = CGPoint(x: screenFrame.midX, y: screenFrame.height + 30)
                flightDuration = 0.5
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

            case .converge:
                let jitter: CGFloat = 26
                start = CGPoint(x: target.x + CGFloat.random(in: -jitter...jitter),
                                y: target.y + CGFloat.random(in: -jitter...jitter))
                flightDuration = 0.8
                delay = Double(index) * 0.015
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
            self.butterflies.forEach { $0.stopHover() }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.6
                self.butterflies.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: {
                self.butterflies.forEach { $0.removeFromSuperview() }
                self.butterflies.removeAll()
                self.isBusy = false
            })
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
