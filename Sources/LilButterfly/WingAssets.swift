import AppKit

/// A rasterized wing design plus the tight bounding box of its actual
/// (non-transparent) artwork, in raster pixel coordinates. The 9 source
/// SVGs don't all fill their viewBox by the same margin, so sizing purely
/// off `image.width`/`image.height` made some designs read as visibly
/// smaller than others even at the same target display width. `inkBounds`
/// lets ButterflyView normalize against the actual wingspan instead.
struct WingAsset {
    let image: CGImage
    let inkBounds: CGRect
}

enum WingAssets {
    /// Filenames (without extension) of the bundled designs, in menu order.
    static func names() -> [String] {
        (1...9).map { "Asset \($0)" }
    }

    /// Pixel scale the SVGs are rasterized at, so bitmap wing layers stay
    /// crisp on Retina displays (contentsScale is set to match, see
    /// ButterflyView).
    static let rasterScale: CGFloat = 3

    private static let assets: [WingAsset] = names().compactMap(loadRasterized)

    /// Returns the pinned asset if a valid index is given, otherwise a
    /// random one.
    static func pick(pinnedIndex: Int?) -> WingAsset {
        if let pinnedIndex, assets.indices.contains(pinnedIndex) {
            return assets[pinnedIndex]
        }
        return assets.randomElement()!
    }

    /// A compact, full-color thumbnail for the design picker.
    static func menuImage(at index: Int, width: CGFloat = 22) -> NSImage? {
        guard assets.indices.contains(index) else { return nil }
        let asset = assets[index]
        let imageBounds = CGRect(x: 0, y: 0, width: asset.image.width, height: asset.image.height)
        let cropRect = asset.inkBounds.integral.intersection(imageBounds)
        guard let cropped = asset.image.cropping(to: cropRect) else { return nil }
        let aspect = CGFloat(cropped.height) / max(CGFloat(cropped.width), 1)
        return NSImage(
            cgImage: cropped,
            size: NSSize(width: width, height: width * aspect)
        )
    }

    private static func loadRasterized(name: String) -> WingAsset? {
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

        guard let cgImage = rep.cgImage else { return nil }
        let bounds = inkBounds(of: rep) ?? CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        return WingAsset(image: cgImage, inkBounds: bounds)
    }

    /// Scans the alpha channel for the tight bounding box of non-transparent
    /// pixels, in raster pixel coordinates (y increasing upward, matching
    /// CGImage/CALayer convention). Returns nil if the image is fully
    /// transparent (shouldn't happen for real art, but guards the crop math).
    private static func inkBounds(of rep: NSBitmapImageRep) -> CGRect? {
        guard let data = rep.bitmapData else { return nil }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let bytesPerRow = rep.bytesPerRow
        let samplesPerPixel = rep.samplesPerPixel
        guard samplesPerPixel >= 4 else { return nil }

        let alphaThreshold: UInt8 = 10
        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1

        for y in 0..<height {
            let row = data + y * bytesPerRow
            for x in 0..<width {
                let alpha = row[x * samplesPerPixel + 3]
                if alpha > alphaThreshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        // Flip Y: NSBitmapImageRep's buffer is stored top-down, but
        // CGImage/CALayer coordinates (and the crop rects ButterflyView
        // builds) are bottom-up.
        let flippedMinY = height - 1 - maxY
        return CGRect(x: minX, y: flippedMinY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
