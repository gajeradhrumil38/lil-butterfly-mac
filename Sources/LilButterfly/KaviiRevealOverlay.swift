import AppKit

/// A short, intentional celebration: every bundled wing design joins the
/// center briefly, with the app's name in the middle, then disappears.
final class KaviiRevealOverlay {
    private let window: OverlayWindow
    private let screenFrame: CGRect
    private var butterflies: [ButterflyView] = []
    private var textLayer: CATextLayer?
    private var isBusy = false

    init(screen: NSScreen) {
        window = OverlayWindow(screen: screen)
        screenFrame = CGRect(origin: .zero, size: screen.frame.size)
    }

    func show() {
        guard !isBusy, let host = window.contentView else { return }
        isBusy = true

        let center = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
        let text = CATextLayer()
        text.string = "Kavii"
        text.font = NSFont.systemFont(ofSize: 42, weight: .semibold)
        text.fontSize = 42
        text.alignmentMode = .center
        text.foregroundColor = NSColor.white.cgColor
        text.shadowColor = NSColor.black.cgColor
        text.shadowOpacity = 0.35
        text.shadowRadius = 8
        text.shadowOffset = CGSize(width: 0, height: -2)
        text.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        text.frame = CGRect(x: center.x - 150, y: center.y - 30, width: 300, height: 70)
        text.opacity = 0
        host.layer?.addSublayer(text)
        textLayer = text

        let count = max(1, WingAssets.names().count)
        let radius: CGFloat = 135
        for index in 0..<count {
            let angle = (CGFloat(index) / CGFloat(count)) * .pi * 2
            let target = CGPoint(x: center.x + cos(angle) * radius,
                                 y: center.y + sin(angle) * radius)
            let start = CGPoint(x: center.x + cos(angle) * (radius + 180),
                                y: center.y + sin(angle) * (radius + 180))
            let butterfly = ButterflyView(center: start, pinnedAssetIndex: index)
            butterfly.alphaValue = 0
            host.addSubview(butterfly)
            butterflies.append(butterfly)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.06) {
                guard self.isBusy else { return }
                butterfly.alphaValue = 1
                butterfly.flyPath(from: start, to: target, duration: 0.8, easeIn: false, completion: nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            guard self.isBusy else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.5)
            text.opacity = 1
            CATransaction.commit()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            guard self.isBusy else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.45
                self.butterflies.forEach { $0.animator().alphaValue = 0 }
                text.opacity = 0
            }, completionHandler: {
                self.butterflies.forEach { $0.removeFromSuperview() }
                self.butterflies.removeAll()
                text.removeFromSuperlayer()
                self.textLayer = nil
                self.isBusy = false
            })
        }
    }
}
