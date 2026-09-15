import AppKit

/// A short, intentional celebration: butterflies arrange themselves into the
/// word "Kavii" instead of drawing the name as a normal text layer.
final class KaviiRevealOverlay {
    private let window: OverlayWindow
    private let screenFrame: CGRect
    private var butterflies: [ButterflyView] = []
    private var isBusy = false

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

        for (index, target) in targets.enumerated() {
            let angle = (CGFloat(index) / CGFloat(max(1, targets.count))) * .pi * 2
            let distance = CGFloat.random(in: 150...230)
            let start = CGPoint(x: target.x + cos(angle) * distance,
                                y: target.y + sin(angle) * distance)
            let butterfly = ButterflyView(
                center: start,
                pinnedAssetIndex: index % assetCount,
                displayWidth: 20
            )
            butterfly.alphaValue = 0
            host.addSubview(butterfly)
            butterflies.append(butterfly)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.035) {
                guard self.isBusy else { return }
                butterfly.alphaValue = 1
                butterfly.flyPath(from: start, to: target, duration: 0.7, easeIn: false, completion: nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            guard self.isBusy else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.45
                self.butterflies.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: {
                self.butterflies.forEach { $0.removeFromSuperview() }
                self.butterflies.removeAll()
                self.isBusy = false
            })
        }
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
