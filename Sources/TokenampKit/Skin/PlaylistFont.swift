import CoreGraphics
import Foundation

/// `plfont` - the Sessions-list bitmap typeface (SPEC 3.2, amendment A1).
///
/// Classic Winamp names a *system* font in `pledit.txt`; Tokenamp ignores that key and draws the
/// playlist rows out of the skin's own 16x6 glyph sheet instead, so the list is made of the same
/// pixels as the hardware around it. There is no vector text anywhere in a skinned window.
///
/// The sheet's pixels are an **ink mask**, not colours: `coverage = mean(r,g,b)/255 * alpha`, and
/// the app composites `tint x coverage` over the row background. Greys are therefore usable as a
/// phosphor halo, which is exactly what Base's font does.
public struct PlaylistFontMetrics: Equatable {
    public var monospace = false
    public var spacing = 1
    /// Advance of a cell with no ink. Defaults to `max(2, cellW/2 - 1)` once the cell size is known.
    public var spaceWidth: Int?
    /// Row pitch of the list, in skin px. Defaults to `cellH + 1`; replaces `layout.playlist.rowHeight`.
    public var rowHeight: Int?
    /// Cell top within the row.
    public var offsetY = 0

    public init() {}

    /// `[PlaylistFont]` INI section; every key optional, every value lenient.
    public static func parse(_ data: Data) -> PlaylistFontMetrics {
        var out = PlaylistFontMetrics()
        let section = INIFile.parse(data).section("PlaylistFont")
        if let v = section["monospace"] { out.monospace = (Int(v.trimmingCharacters(in: .whitespaces)) ?? 0) != 0 }
        if let v = section["spacing"], let n = Int(v.trimmingCharacters(in: .whitespaces)) { out.spacing = max(0, min(16, n)) }
        if let v = section["spacewidth"], let n = Int(v.trimmingCharacters(in: .whitespaces)) { out.spaceWidth = max(0, min(64, n)) }
        if let v = section["rowheight"], let n = Int(v.trimmingCharacters(in: .whitespaces)) { out.rowHeight = max(1, min(64, n)) }
        if let v = section["offsety"], let n = Int(v.trimmingCharacters(in: .whitespaces)) { out.offsetY = max(-32, min(32, n)) }
        return out
    }
}

/// A usable `plfont` sheet plus its metrics, with tinted glyph images cached per colour.
public final class PlaylistFont {

    /// 16 columns x 6 rows, row-major; cell k holds character code 32+k, and cell 95 (code 127)
    /// holds the ellipsis.
    public static let columns = 16
    public static let rows = 6
    public static let cellCount = columns * rows          // 96
    public static let ellipsisCell = cellCount - 1        // code 127

    public let cellW: Int
    public let cellH: Int
    public let rowHeight: Int
    public let offsetY: Int
    public let spacing: Int
    public let spaceWidth: Int
    public let monospace: Bool

    /// coverage[y * sheetWidth + x], 0...255.
    private let coverage: [UInt8]
    private let sheetWidth: Int
    private let sheetHeight: Int

    /// Ink extent of one cell. `left > right` means the cell is blank.
    private struct Extent {
        let left: Int
        let right: Int
        var isBlank: Bool { left > right }
    }
    private let extents: [Extent]
    /// Ink rows of each cell at `hardInkThreshold`; `top > bottom` means the cell is blank.
    private let hardRows: [(top: Int, bottom: Int)]

    private struct GlyphKey: Hashable {
        let cell: Int
        let tint: UInt32
        /// Cut hard at `hardInkThreshold` (Token Flow labels) rather than composited by coverage.
        let hard: Bool
    }
    private var glyphCache: [GlyphKey: CGImage?] = [:]
    private let lock = NSLock()

    /// nil when the sheet is not a clean 16x6 grid (SPEC 3.2: "the font is ignored").
    public init?(sheet: CGImage, metrics: PlaylistFontMetrics?) {
        let w = sheet.width, h = sheet.height
        guard w > 0, h > 0, w % PlaylistFont.columns == 0, h % PlaylistFont.rows == 0 else { return nil }
        cellW = w / PlaylistFont.columns
        cellH = h / PlaylistFont.rows
        guard cellW > 0, cellH > 0 else { return nil }
        sheetWidth = w
        sheetHeight = h

        guard let cov = PlaylistFont.coverageMask(of: sheet) else { return nil }
        coverage = cov

        let m = metrics ?? PlaylistFontMetrics()
        monospace = m.monospace
        spacing = m.spacing
        spaceWidth = m.spaceWidth ?? max(2, cellW / 2 - 1)
        rowHeight = m.rowHeight ?? (cellH + 1)
        offsetY = m.offsetY

        // An *ink column* is a cell column holding any pixel with coverage >= 0.5.
        var ext: [Extent] = []
        ext.reserveCapacity(PlaylistFont.cellCount)
        for k in 0..<PlaylistFont.cellCount {
            let cx = (k % PlaylistFont.columns) * cellW
            let cy = (k / PlaylistFont.columns) * cellH
            var left = cellW, right = -1
            for x in 0..<cellW {
                var inked = false
                for y in 0..<cellH where cov[(cy + y) * w + cx + x] >= 128 { inked = true; break }
                if inked {
                    if x < left { left = x }
                    right = x
                }
            }
            ext.append(Extent(left: left, right: right))
        }
        extents = ext

        // The rows each cell inks at the same half-coverage cut, for Token Flow's hard labels.
        var rows: [(top: Int, bottom: Int)] = []
        rows.reserveCapacity(PlaylistFont.cellCount)
        for k in 0..<PlaylistFont.cellCount {
            let cx = (k % PlaylistFont.columns) * cellW
            let cy = (k / PlaylistFont.columns) * cellH
            var top = cellH, bottom = -1
            for y in 0..<cellH {
                for x in 0..<cellW where Int(cov[(cy + y) * w + cx + x]) >= PlaylistFont.hardInkThreshold {
                    if y < top { top = y }
                    bottom = y
                    break
                }
            }
            rows.append((top: top, bottom: bottom))
        }
        hardRows = rows
    }

    /// Premultiplied RGBA of the sheet over a transparent black backdrop: for a pixel of colour C
    /// and alpha a the stored value is C*a, so `mean(r,g,b)/255` *is* `mean(C)/255 * a` - the
    /// coverage formula in SPEC 3.2, with no double-multiplication.
    private static func coverageMask(of image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, w * h <= 16_777_216 else { return nil }
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.setShouldAntialias(false)
            ctx.interpolationQuality = .none
            // An unflipped bitmap context stores its top row first, and drawing an image upright
            // keeps that order: buffer row == image row.
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            return true
        }
        guard ok else { return nil }
        var out = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let r = Int(buffer[i * 4]), g = Int(buffer[i * 4 + 1]), b = Int(buffer[i * 4 + 2])
            out[i] = UInt8(min(255, (r + g + b + 1) / 3))
        }
        return out
    }

    // MARK: - Character mapping

    /// Fold to the 32...126 range the sheet can draw; the ellipsis keeps its own cell.
    public static func sanitize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .widthInsensitive],
                               locale: Locale(identifier: "en_US_POSIX"))
        var out = String()
        out.reserveCapacity(folded.count)
        for ch in folded {
            switch ch {
            case "\u{2026}": out.append(ch)                                   // ellipsis: its own cell
            case "\u{2018}", "\u{2019}", "\u{02BC}": out.append("'")
            case "\u{201C}", "\u{201D}": out.append("\"")
            case "\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}": out.append("-")
            case "\u{00A0}": out.append(" ")
            default:
                if let a = ch.asciiValue, a >= 32, a <= 126 { out.append(ch) } else { out.append("?") }
            }
        }
        return out
    }

    /// Cell index for an already-sanitized character, or nil when it has none.
    public func cell(for ch: Character) -> Int? {
        if ch == "\u{2026}" { return PlaylistFont.ellipsisCell }
        guard let a = ch.asciiValue, a >= 32, a <= 126 else { return nil }
        let k = Int(a) - 32
        return k < PlaylistFont.cellCount ? k : nil
    }

    // MARK: - Metrics

    /// Pen advance for one sanitized character.
    public func advance(_ ch: Character) -> Int {
        guard let k = cell(for: ch) else { return spaceWidth }
        if monospace { return cellW }
        let e = extents[k]
        if e.isBlank { return spaceWidth }
        return e.right - e.left + 1 + spacing
    }

    /// Width of a whole sanitized string; the trailing inter-glyph gap is not counted, so
    /// right-aligned text sits flush against its margin.
    public func measure(_ s: String) -> Int {
        var w = 0
        var lastWasInked = false
        for ch in s {
            w += advance(ch)
            if let k = cell(for: ch), !monospace { lastWasInked = !extents[k].isBlank } else { lastWasInked = false }
        }
        if lastWasInked { w -= spacing }
        return max(0, w)
    }

    /// Truncate with the ellipsis glyph so the text fits `maxWidth`.
    public func truncate(_ s: String, maxWidth: Int) -> String {
        guard maxWidth > 0 else { return "" }
        if measure(s) <= maxWidth { return s }
        var chars = Array(s)
        let dots = "\u{2026}"
        while !chars.isEmpty {
            chars.removeLast()
            let candidate = String(chars) + dots
            if measure(candidate) <= maxWidth { return candidate }
        }
        return ""
    }

    // MARK: - Drawing

    /// One tinted glyph plus where to put it relative to the pen.
    /// SPEC 3.2: the blitted source columns are `[L-1, R+1]` clipped to the cell, placed at `pen-1`,
    /// so a one-pixel halo survives and simply overlaps the spacing.
    private func glyphImage(cell k: Int, tint: CGColor, hard: Bool = false) -> (image: CGImage, dx: Int)? {
        let (tr, tg, tb) = PlaylistFont.components(tint)
        let key = GlyphKey(cell: k, tint: (UInt32(tr) << 16) | (UInt32(tg) << 8) | UInt32(tb), hard: hard)
        lock.lock()
        if let hit = glyphCache[key] {
            lock.unlock()
            guard let image = hit else { return nil }
            return (image, monospace ? 0 : glyphOffset(cell: k))
        }
        lock.unlock()

        let e = extents[k]
        let x0: Int, x1: Int
        if monospace {
            x0 = 0; x1 = cellW - 1
        } else {
            guard !e.isBlank else {
                lock.lock(); glyphCache[key] = .some(nil); lock.unlock()
                return nil
            }
            x0 = max(0, e.left - 1)
            x1 = min(cellW - 1, e.right + 1)
        }
        let w = x1 - x0 + 1
        guard w > 0, cellH > 0 else { return nil }

        let cx = (k % PlaylistFont.columns) * cellW
        let cy = (k / PlaylistFont.columns) * cellH
        var pixels = [UInt8](repeating: 0, count: w * cellH * 4)
        for y in 0..<cellH {
            for x in 0..<w {
                var cov = Int(coverage[(cy + y) * sheetWidth + cx + x0 + x])
                if hard { cov = cov >= PlaylistFont.hardInkThreshold ? 255 : 0 }
                let i = (y * w + x) * 4
                // Premultiplied: tint x coverage, alpha = coverage (rounded, not truncated).
                pixels[i] = UInt8((tr * cov + 127) / 255)
                pixels[i + 1] = UInt8((tg * cov + 127) / 255)
                pixels[i + 2] = UInt8((tb * cov + 127) / 255)
                pixels[i + 3] = UInt8(cov)
            }
        }
        let image = PlaylistFont.makeImage(pixels: pixels, width: w, height: cellH)
        lock.lock(); glyphCache[key] = .some(image); lock.unlock()
        guard let image else { return nil }
        return (image, monospace ? 0 : glyphOffset(cell: k))
    }

    /// Where the blitted strip starts relative to the pen.
    private func glyphOffset(cell k: Int) -> Int {
        let e = extents[k]
        guard !e.isBlank else { return 0 }
        let wanted = e.left - 1                      // may be -1: then the clip eats one column
        let actual = max(0, wanted)
        return -1 + (actual - wanted)
    }

    private static func components(_ color: CGColor) -> (Int, Int, Int) {
        guard let c = color.components, c.count >= 3 else { return (255, 255, 255) }
        func q(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return (q(c[0]), q(c[1]), q(c[2]))
    }

    private static func makeImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Draw `text` (already sanitized) with its cell tops at `y`. Returns the pen's end x.
    @discardableResult
    public func draw(_ text: String, on canvas: SkinCanvas, x: Int, y: Int, tint: CGColor) -> Int {
        var pen = x
        for ch in text {
            if let k = cell(for: ch), let g = glyphImage(cell: k, tint: tint) {
                canvas.draw(g.image, in: CGRect(x: CGFloat(pen + g.dx), y: CGFloat(y),
                                                width: CGFloat(g.image.width), height: CGFloat(g.image.height)))
            }
            pen += advance(ch)
        }
        return pen
    }

    // MARK: - Hard ink (Token Flow labels)

    /// Token Flow sets its labels over a live field, where a glyph's grey halo does not read as
    /// phosphor glow but as blur - and on a sheet whose greys fill the whole cell, as a faint box
    /// behind every letter. There the sheet is cut hard instead: coverage at or above this is full
    /// ink, anything below is nothing. It is the same half-coverage cut SPEC 3.2 uses to decide
    /// what an ink column is, so a hard label keeps exactly the strokes that set its advance and
    /// its width is the width `measure` already reports. The Sessions list never takes this path.
    public static let hardInkThreshold = 128

    /// Where a string's hard ink lands, relative to the pen start and the cell top.
    public struct InkBox: Equatable {
        public var x: Int
        public var y: Int
        public var w: Int
        public var h: Int
    }

    /// True when the sheet's code-127 cell really holds an ellipsis rather than nothing.
    public var hasEllipsis: Bool { !extents[PlaylistFont.ellipsisCell].isBlank }

    /// Hard-ink rows of the capitals and figures, relative to the cell top: the box a label is
    /// placed by, so labels share one baseline whatever letters they happen to contain.
    public var capRows: (top: Int, height: Int) {
        var top = cellH, bottom = -1
        for ch in "EHIMNTX0158" {
            guard let k = cell(for: ch) else { continue }
            let r = hardRows[k]
            guard r.top <= r.bottom else { continue }
            top = min(top, r.top)
            bottom = max(bottom, r.bottom)
        }
        return bottom >= top ? (top, bottom - top + 1) : (0, cellH)
    }

    /// The hard ink of `text` (already sanitized) set from pen 0, or nil when nothing inks.
    public func hardInkBox(_ text: String) -> InkBox? {
        var pen = 0
        var x0 = Int.max, x1 = Int.min, y0 = Int.max, y1 = Int.min
        for ch in text {
            if let k = cell(for: ch) {
                let e = extents[k], r = hardRows[k]
                if !e.isBlank, r.top <= r.bottom {
                    // Proportional glyphs blit column L at the pen; monospace cells blit whole.
                    let left = monospace ? pen + e.left : pen
                    let right = monospace ? pen + e.right : pen + e.right - e.left
                    x0 = min(x0, left); x1 = max(x1, right)
                    y0 = min(y0, r.top); y1 = max(y1, r.bottom)
                }
            }
            pen += advance(ch)
        }
        guard x1 >= x0, y1 >= y0 else { return nil }
        return InkBox(x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1)
    }

    /// `draw`, cut hard at `hardInkThreshold`: the same glyphs at the same pen positions, as
    /// solid ink with nothing in between.
    @discardableResult
    public func drawHardInk(_ text: String, on canvas: SkinCanvas, x: Int, y: Int, tint: CGColor) -> Int {
        var pen = x
        for ch in text {
            if let k = cell(for: ch), let g = glyphImage(cell: k, tint: tint, hard: true) {
                canvas.draw(g.image, in: CGRect(x: CGFloat(pen + g.dx), y: CGFloat(y),
                                                width: CGFloat(g.image.width), height: CGFloat(g.image.height)))
            }
            pen += advance(ch)
        }
        return pen
    }

    /// Every hard-ink pixel of `text` (already sanitized) set from pen 0, relative to the pen and
    /// the cell top: exactly the pixels `drawHardInk` lights, for writing straight into a bitmap.
    public func forEachHardInkPixel(_ text: String, _ body: (Int, Int) -> Void) {
        var pen = 0
        for ch in text {
            if let k = cell(for: ch) {
                let e = extents[k], r = hardRows[k]
                if !e.isBlank, r.top <= r.bottom {
                    let cx = (k % PlaylistFont.columns) * cellW
                    let cy = (k / PlaylistFont.columns) * cellH
                    // A proportional glyph lands with its first ink column on the pen.
                    let shift = monospace ? pen : pen - e.left
                    for y in r.top...r.bottom {
                        let row = (cy + y) * sheetWidth + cx
                        for x in e.left...e.right where Int(coverage[row + x]) >= PlaylistFont.hardInkThreshold {
                            body(shift + x, y)
                        }
                    }
                }
            }
            pen += advance(ch)
        }
    }

    /// Whether one pixel of a cell is hard ink (for the self-test).
    func isHardInk(cell k: Int, x: Int, y: Int) -> Bool {
        guard k >= 0, k < PlaylistFont.cellCount, x >= 0, x < cellW, y >= 0, y < cellH else { return false }
        let cx = (k % PlaylistFont.columns) * cellW
        let cy = (k / PlaylistFont.columns) * cellH
        return Int(coverage[(cy + y) * sheetWidth + cx + x]) >= PlaylistFont.hardInkThreshold
    }
}
