import AppKit

enum WingAssets {
    /// Filenames (without extension) of the bundled designs, in menu order.
    static func names() -> [String] {
        (1...9).map { "Asset \($0)" }
    }

    /// Pixel scale the SVGs are rasterized at, so bitmap wing layers stay
    /// crisp on Retina displays (contentsScale is set to match, see
    /// ButterflyView).
    static let rasterScale: CGFloat = 3

    private static let images: [CGImage] = names().compactMap(loadRasterized)

    /// Returns the pinned asset if a valid index is given, otherwise a
    /// random one.
    static func pick(pinnedIndex: Int?) -> CGImage {
        if let pinnedIndex, images.indices.contains(pinnedIndex) {
            return images[pinnedIndex]
        }
        return images.randomElement()!
    }

    private static func loadRasterized(name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Wings"),
              let image = NSImage(contentsOf: url)
        else { return nil }

        let pixelSize = CGSize(width: image.size.width * rasterScale, height: image.size.height * rasterScale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = image.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        return rep.cgImage
    }
}
