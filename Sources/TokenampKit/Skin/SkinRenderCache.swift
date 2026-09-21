import CoreGraphics
import Foundation

/// Per-skin derived images that would otherwise be rebuilt on every animation frame.
///
/// The visualizer is the hot path: a naive implementation fills ~600 one-pixel rectangles per
/// frame (the dot grid plus one rect per bar row), 30 times a second. Pre-baking the background
/// and the bar colour ramp turns that into a couple of dozen image blits.
final class SkinRenderCache {

    private unowned let skin: Skin
    private let lock = NSLock()

    private var backgrounds: [Int: CGImage] = [:]
    private var barStrip: CGImage?
    private var barSegments: [Int: CGImage] = [:]
    private var miniStrip: CGImage?
    private var miniSegments: [Int: CGImage] = [:]
    private var graphRowColors: [CGColor]?

    init(skin: Skin) { self.skin = skin }

    private func key(_ w: Int, _ h: Int) -> Int { (w << 16) | h }

    /// Visualizer background: colour 0 with the colour-1 dot grid (dots at even x on odd y).
    func visualizerBackground(width: Int, height: Int) -> CGImage? {
        lock.lock()
        if let hit = backgrounds[key(width, height)] { lock.unlock(); return hit }
        lock.unlock()
        let vc = skin.visColors
        let image = ImageMaker.make(width: width, height: height) { c in
            c.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), vc.color(0))
            let dot = vc.color(1)
            c.ctx.setFillColor(dot)
            var y = 1
            while y < height {
                var x = 0
                while x < width {
                    c.ctx.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1))
                    x += 2
                }
                y += 2
            }
        }
        guard let image else { return nil }
        lock.lock()
        backgrounds[key(width, height)] = image
        lock.unlock()
        return image
    }

    /// The bottom `height` rows of a bar, already coloured (colours 2...17, index 2 at the top).
    func barSegment(height: Int, rows: Int, width: Int) -> CGImage? {
        guard height > 0, height <= rows else { return nil }
        lock.lock()
        if let hit = barSegments[height] { lock.unlock(); return hit }
        lock.unlock()
        if barStrip == nil {
            let vc = skin.visColors
            barStrip = ImageMaker.make(width: width, height: rows) { c in
                for r in 0..<rows {
                    c.fill(CGRect(x: 0, y: CGFloat(r), width: CGFloat(width), height: 1),
                           vc.color(2 + min(15, r)))
                }
            }
        }
        guard let strip = barStrip,
              let seg = strip.cropping(to: CGRect(x: 0, y: CGFloat(rows - height),
                                                  width: CGFloat(width), height: CGFloat(height)))
        else { return nil }
        lock.lock()
        barSegments[height] = seg
        lock.unlock()
        return seg
    }

    /// Same, for the window-shade strip, where the 16-colour ramp is squeezed into 5 rows.
    func miniSegment(height: Int, rows: Int, width: Int) -> CGImage? {
        guard height > 0, height <= rows else { return nil }
        lock.lock()
        if let hit = miniSegments[height] { lock.unlock(); return hit }
        lock.unlock()
        if miniStrip == nil {
            let vc = skin.visColors
            miniStrip = ImageMaker.make(width: width, height: rows) { c in
                for r in 0..<rows {
                    c.fill(CGRect(x: 0, y: CGFloat(r), width: CGFloat(width), height: 1),
                           vc.color(2 + min(15, r * 16 / max(1, rows))))
                }
            }
        }
        guard let strip = miniStrip,
              let seg = strip.cropping(to: CGRect(x: 0, y: CGFloat(rows - height),
                                                  width: CGFloat(width), height: CGFloat(height)))
        else { return nil }
        lock.lock()
        miniSegments[height] = seg
        lock.unlock()
        return seg
    }

    /// The 19 row colours of `EQ_GRAPH_LINE_COLORS`, read once out of the skin's 1x19 strip.
    func eqGraphRowColors(height: Int) -> [CGColor] {
        lock.lock()
        if let hit = graphRowColors, hit.count == height { lock.unlock(); return hit }
        lock.unlock()
        var colors: [CGColor] = []
        if let strip = skin.image(Spr.EQ_GRAPH_LINE_COLORS),
           let ctx = CGContext(data: nil, width: 1, height: strip.height, bitsPerComponent: 8, bytesPerRow: 4,
                               space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: strip.height))
            if let buffer = ctx.data {
                let bytes = buffer.bindMemory(to: UInt8.self, capacity: 4 * strip.height)
                for row in 0..<strip.height {
                    // A CGBitmapContext's buffer is stored top-row-first, and drawing an upright
                    // image into an unflipped context keeps that order: buffer row == image row.
                    let i = row * 4
                    colors.append(CGColor(srgbRed: CGFloat(bytes[i]) / 255, green: CGFloat(bytes[i + 1]) / 255,
                                          blue: CGFloat(bytes[i + 2]) / 255, alpha: 1))
                }
            }
        }
        while colors.count < height { colors.append(skin.visColors.color(18)) }
        let result = Array(colors.prefix(height))
        lock.lock()
        graphRowColors = result
        lock.unlock()
        return result
    }
}
