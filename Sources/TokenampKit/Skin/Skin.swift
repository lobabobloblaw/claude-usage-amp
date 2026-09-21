import CoreGraphics
import Foundation

/// A loaded classic skin: its sheets as `CGImage`s plus the three text files.
///
/// Sprite lookup goes through here so that every miss has exactly one recovery path:
/// this skin's sheet -> the Base skin's sheet -> nothing drawn (never a crash).
public final class Skin {

    public let name: String
    public let sourceURL: URL?
    public let visColors: VisColors
    public let pledit: PleditColors
    public let regions: SkinRegions
    public private(set) var warnings: [String]

    /// Sheets this skin actually provides.
    private let ownSheets: [SheetID: CGImage]
    /// This skin's own `plfont` sheet (SPEC 3.2), already checked to be a clean 16x6 grid.
    private let ownPlfontSheet: CGImage?
    private let ownPlfontMetrics: PlaylistFontMetrics?
    private var spriteCache: [SpriteRef: CGImage] = [:]
    private var rectCache: [SheetRect: CGImage] = [:]
    private let lock = NSLock()

    private struct SheetRect: Hashable {
        let sheet: SheetID
        let rect: SpriteRect
    }

    public init(name: String, sourceURL: URL?, sheets: [SheetID: CGImage], visColors: VisColors,
                pledit: PleditColors, regions: SkinRegions, plfontSheet: CGImage? = nil,
                plfontMetrics: PlaylistFontMetrics? = nil, warnings: [String]) {
        self.name = name
        self.sourceURL = sourceURL
        self.ownSheets = sheets
        self.visColors = visColors
        self.pledit = pledit
        self.regions = regions
        self.ownPlfontSheet = plfontSheet
        self.ownPlfontMetrics = plfontMetrics
        self.warnings = warnings
    }

    // MARK: - The Base skin (per-sheet fallback)

    private static var baseStorage: Skin?
    private static var baseResolved = false

    /// The skin every other skin falls back to, sheet by sheet. Loaded from the bundled `Base.wsz`
    /// when one is on disk; otherwise a small procedurally drawn stand-in so the app is never
    /// blank and never crashes.
    public static var base: Skin {
        if let s = baseStorage { return s }
        baseResolved = true
        if let url = ResourceLocator.bundledSkin(named: "Base"),
           let loaded = try? SkinLoader.load(url: url, name: "Base") {
            baseStorage = loaded
            return loaded
        }
        let synth = FallbackSkin.make()
        baseStorage = synth
        return synth
    }

    /// True when the Base fallback is the procedural stand-in rather than a real bundled skin.
    public static var baseIsSynthetic: Bool {
        _ = base
        return base.sourceURL == nil
    }

    /// Forget the cached Base skin (used after the user installs skins, and by --selftest).
    public static func resetBase() {
        baseStorage = nil
        baseResolved = false
    }

    public var isBase: Bool { self === Skin.base }

    // MARK: - Sheets and sprites

    /// This skin's sheet, or Base's, or nil.
    public func sheet(_ id: SheetID) -> CGImage? {
        if let own = ownSheets[id] { return own }
        if self === Skin.base { return nil }
        return Skin.base.rawSheet(id)
    }

    /// Only this skin's own sheet - no fallback. Used to answer "does this skin ship X?".
    public func rawSheet(_ id: SheetID) -> CGImage? { ownSheets[id] }

    public func hasOwnSheet(_ id: SheetID) -> Bool { ownSheets[id] != nil }

    /// Crop one named sprite. Returns nil when the sheet is absent everywhere or when the rect
    /// falls outside an undersized sheet (old skins) - callers simply draw nothing.
    public func image(_ ref: SpriteRef) -> CGImage? {
        lock.lock()
        if let hit = spriteCache[ref] { lock.unlock(); return hit }
        lock.unlock()
        guard let img = crop(ref.sheet, ref.rect) else { return nil }
        lock.lock()
        spriteCache[ref] = img
        lock.unlock()
        return img
    }

    /// Crop an arbitrary rect out of a sheet (frames, font glyphs, colour strips).
    public func crop(_ id: SheetID, _ rect: SpriteRect) -> CGImage? {
        let key = SheetRect(sheet: id, rect: rect)
        lock.lock()
        if let hit = rectCache[key] { lock.unlock(); return hit }
        lock.unlock()

        guard rect.w > 0, rect.h > 0 else { return nil }
        // Prefer our own sheet; if the rect does not fit inside it, try Base before giving up.
        var image: CGImage?
        if let own = ownSheets[id], fits(rect, own) {
            image = own.cropping(to: rect.cg)
        } else if self !== Skin.base, let b = Skin.base.rawSheet(id), fits(rect, b) {
            image = b.cropping(to: rect.cg)
        } else if let own = ownSheets[id] {
            // Undersized sheet: clip the rect to what exists rather than dropping the sprite.
            let clipped = CGRect(x: rect.cg.minX, y: rect.cg.minY,
                                 width: min(rect.cg.width, CGFloat(own.width) - rect.cg.minX),
                                 height: min(rect.cg.height, CGFloat(own.height) - rect.cg.minY))
            if clipped.width >= 1, clipped.height >= 1, clipped.minX >= 0, clipped.minY >= 0 {
                image = own.cropping(to: clipped)
            }
        }
        guard let image else { return nil }
        lock.lock()
        rectCache[key] = image
        lock.unlock()
        return image
    }

    private func fits(_ r: SpriteRect, _ img: CGImage) -> Bool {
        r.x >= 0 && r.y >= 0 && r.x + r.w <= img.width && r.y + r.h <= img.height
    }

    /// Background frame `i` of a frame-strip sheet (volume/balance heat ramp, EQ slider wells).
    public func frame(_ id: SheetID, _ index: Int) -> CGImage? {
        guard let spec = SkinSpec.sheets[id], let frames = spec.frames else { return nil }
        // balance.bmp is commonly missing; classic Winamp reads volume.bmp with the same rects.
        if id == .balance, ownSheets[.balance] == nil, ownSheets[.volume] != nil {
            return crop(.volume, frames.rect(index))
        }
        return crop(id, frames.rect(index))
    }

    // MARK: - Digits

    /// `nums_ex.bmp` when present, else `numbers.bmp` (SPEC 3).
    public var digitSheet: SheetID {
        if ownSheets[.numsEx] != nil { return .numsEx }
        if ownSheets[.numbers] != nil { return .numbers }
        if self !== Skin.base, Skin.base.rawSheet(.numsEx) != nil { return .numsEx }
        return .numbers
    }

    public var hasExtendedDigits: Bool { digitSheet == .numsEx }

    /// One time digit. `ch` is "0"..."9", " " (blank) or "-" (minus, nums_ex only).
    public func digitSprite(_ ch: Character) -> CGImage? {
        let sheet = digitSheet
        let name: String
        switch ch {
        case "0"..."9": name = "DIGIT_\(ch)"
        case "-": name = "DIGIT_MINUS"
        default: name = "DIGIT_BLANK"
        }
        guard let rect = SkinSpec.rect(sheet, name) ?? SkinSpec.rect(sheet, "DIGIT_BLANK") else { return nil }
        return crop(sheet, rect)
    }

    // MARK: - Bitmap font

    private var fontStore: BitmapFont?
    private var renderCacheStore: SkinRenderCache?

    /// Derived images (visualizer background, bar ramps, EQ graph colours) built on first use.
    var renderCache: SkinRenderCache {
        if let c = renderCacheStore { return c }
        let c = SkinRenderCache(skin: self)
        renderCacheStore = c
        return c
    }

    public var font: BitmapFont {
        if let f = fontStore { return f }
        let f = BitmapFont(skin: self)
        fontStore = f
        return f
    }

    // MARK: - plfont (SPEC 3.2)

    private var plFontStore: PlaylistFont??

    /// True when this skin ships its own usable playlist typeface.
    public var hasOwnPlaylistFont: Bool { ownPlfontSheet != nil }

    /// The Sessions-list typeface: this skin's own, else the bundled Base skin's (tinted with
    /// *this* skin's pledit colours, because the tint is applied at draw time). nil only when even
    /// Base has none, and the playlist then falls back to the classic 5x6 text font - never to a
    /// system font.
    public var playlistFont: PlaylistFont? {
        if let cached = plFontStore { return cached }
        var resolved: PlaylistFont?
        if let sheet = ownPlfontSheet {
            resolved = PlaylistFont(sheet: sheet, metrics: ownPlfontMetrics)
        }
        if resolved == nil, self !== Skin.base {
            resolved = Skin.base.playlistFont
        }
        plFontStore = .some(resolved)
        return resolved
    }

    /// Row pitch of the Sessions list: the skin font's `RowHeight` when it has one (SPEC 3.2
    /// explicitly replaces `layout.playlist.rowHeight`), else the layout default.
    public var playlistRowHeight: Int {
        playlistFont?.rowHeight ?? Layout.Playlist.rowHeight
    }

    // MARK: - Diagnostics

    public var missingSheets: [SheetID] {
        SkinSpec.sheetOrder.filter { ownSheets[$0] == nil }
    }

    public func describeSheets() -> [String] {
        SkinSpec.sheetOrder.compactMap { id in
            guard let spec = SkinSpec.sheets[id] else { return nil }
            if let img = ownSheets[id] {
                return "\(spec.file) \(img.width)x\(img.height)"
            }
            return "\(spec.file) - (Base)"
        }
    }

    public func addWarning(_ s: String) { warnings.append(s) }
}
