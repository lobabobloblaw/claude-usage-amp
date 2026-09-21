import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// A CGContext whose user space is **skin pixels with the origin at the top-left and y growing
/// down**, at an integer scale factor.
///
/// Every renderer draws through this type, so the classic trap - `CGContext.draw(image:in:)`
/// renders a CGImage upside down in a y-flipped space - is handled exactly once, in `draw(_:at:)`.
/// The live `NSView`s and the offscreen snapshot renderer share it, which is what keeps the two
/// outputs identical.
public final class SkinCanvas {

    public let ctx: CGContext
    public let scale: CGFloat

    /// Wrap a context that is already in skin-pixel, y-down user space (a flipped NSView).
    public init(ctx: CGContext, scale: CGFloat) {
        self.ctx = ctx
        self.scale = scale
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
    }

    /// Wrap a bottom-up bitmap context: flip it and scale it into skin-pixel space.
    public static func bitmap(context: CGContext, pixelHeight: Int, scale: CGFloat) -> SkinCanvas {
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        return SkinCanvas(ctx: context, scale: scale)
    }

    /// A fresh offscreen canvas of `width` x `height` skin pixels at `scale`.
    public static func offscreen(width: Int, height: Int, scale: Int) -> SkinCanvas? {
        let pw = width * scale, ph = height * scale
        guard pw > 0, ph > 0,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.setAllowsAntialiasing(true)
        return bitmap(context: ctx, pixelHeight: ph, scale: CGFloat(scale))
    }

    public func makeImage() -> CGImage? { ctx.makeImage() }

    // MARK: - State

    public func save() { ctx.saveGState() }
    public func restore() { ctx.restoreGState() }

    public func clip(to rect: CGRect) { ctx.clip(to: rect) }
    public func clip(to rect: SpriteRect) { ctx.clip(to: rect.cg) }

    // MARK: - Sprites

    /// Draw a CGImage upright at `rect` in skin-pixel, y-down space.
    ///
    /// THE flip helper. A CGImage's first row is its top row, but `CGContext.draw` places the
    /// image bottom-up in user space; because our user space is already y-flipped the two flips
    /// would cancel into an upside-down sprite. Undo it locally, once, here.
    public func draw(_ image: CGImage, in rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    public func draw(_ image: CGImage, at point: CGPoint) {
        draw(image, in: CGRect(x: point.x, y: point.y, width: CGFloat(image.width), height: CGFloat(image.height)))
    }

    public func draw(_ image: CGImage?, at x: Int, _ y: Int) {
        guard let image else { return }
        draw(image, at: CGPoint(x: CGFloat(x), y: CGFloat(y)))
    }

    /// Draw a sprite at its layout rect, sized by the sprite (layout rects and sprite rects agree
    /// in sprites.json, but the sprite wins so an undersized sheet still lands in the right place).
    public func draw(_ image: CGImage?, at rect: SpriteRect) {
        guard let image else { return }
        draw(image, in: CGRect(x: CGFloat(rect.x), y: CGFloat(rect.y),
                               width: CGFloat(image.width), height: CGFloat(image.height)))
    }

    /// Repeat a sprite horizontally to fill `[x0, x1)` at `y`.
    public func tileH(_ image: CGImage?, from x0: Int, to x1: Int, y: Int) {
        guard let image, image.width > 0, x1 > x0 else { return }
        save()
        clip(to: CGRect(x: CGFloat(x0), y: CGFloat(y), width: CGFloat(x1 - x0), height: CGFloat(image.height)))
        var x = x0
        while x < x1 {
            draw(image, at: x, y)
            x += image.width
        }
        restore()
    }

    /// Repeat a sprite vertically to fill `[y0, y1)` at `x`.
    public func tileV(_ image: CGImage?, from y0: Int, to y1: Int, x: Int) {
        guard let image, image.height > 0, y1 > y0 else { return }
        save()
        clip(to: CGRect(x: CGFloat(x), y: CGFloat(y0), width: CGFloat(image.width), height: CGFloat(y1 - y0)))
        var y = y0
        while y < y1 {
            draw(image, at: x, y)
            y += image.height
        }
        restore()
    }

    // MARK: - Solid pixels

    /// No gstate churn: the canvas already has antialiasing off, and the visualizer calls this
    /// hundreds of times per frame.
    public func fill(_ rect: CGRect, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fill(rect)
    }

    public func fill(_ rect: SpriteRect, _ color: CGColor) { fill(rect.cg, color) }

    public func pixel(_ x: Int, _ y: Int, _ color: CGColor) {
        fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1), color)
    }

    public func vline(x: Int, y0: Int, y1: Int, _ color: CGColor) {
        let lo = min(y0, y1), hi = max(y0, y1)
        fill(CGRect(x: CGFloat(x), y: CGFloat(lo), width: 1, height: CGFloat(hi - lo + 1)), color)
    }

    public func hline(y: Int, x0: Int, x1: Int, _ color: CGColor) {
        let lo = min(x0, x1), hi = max(x0, x1)
        fill(CGRect(x: CGFloat(lo), y: CGFloat(y), width: CGFloat(hi - lo + 1), height: 1), color)
    }

    // MARK: - Bitmap text

    /// Draw a string in the skin's 5x6 bitmap font. Returns the x just past the last glyph.
    @discardableResult
    public func text(_ string: String, font: BitmapFont, x: Int, y: Int, maxGlyphs: Int = .max) -> Int {
        var cx = x
        var n = 0
        for ch in BitmapFont.sanitize(string) {
            if n >= maxGlyphs { break }
            if let g = font.glyph(ch) {
                draw(g, in: CGRect(x: CGFloat(cx), y: CGFloat(y),
                                   width: CGFloat(BitmapFont.glyphWidth), height: CGFloat(BitmapFont.glyphHeight)))
            }
            cx += BitmapFont.glyphWidth
            n += 1
        }
        return cx
    }

    /// Right-align a string into a field that is `glyphs` cells wide.
    @discardableResult
    public func textRightAligned(_ string: String, font: BitmapFont, x: Int, y: Int, glyphs: Int) -> Int {
        let s = String(BitmapFont.sanitize(string).suffix(glyphs))
        let pad = glyphs - s.count
        return text(String(repeating: " ", count: max(0, pad)) + s, font: font, x: x, y: y, maxGlyphs: glyphs)
    }

    // NOTE: there is deliberately no vector-text helper here. SPEC 3 / amendment A1: nothing in a
    // skinned window is drawn with a system font - the playlist rows use the skin's own bitmap
    // `plfont` (see PlaylistFont.swift) and everything else uses the classic 5x6 text.bmp font.
}

// MARK: - Image helpers

public enum ImageMaker {
    /// Build a CGImage by drawing into a skin-pixel, y-down canvas of exactly `width` x `height`.
    public static func make(width: Int, height: Int, _ body: (SkinCanvas) -> Void) -> CGImage? {
        guard let canvas = SkinCanvas.offscreen(width: width, height: height, scale: 1) else { return nil }
        body(canvas)
        return canvas.makeImage()
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
