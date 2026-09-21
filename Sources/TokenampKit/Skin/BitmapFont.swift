import CoreGraphics
import Foundation

/// The classic 5x6 bitmap font that lives in `text.bmp`.
///
/// Cell `[row, col]` holds `SkinFontSpec.rows[row][col]`; lower case folds to upper case and
/// anything unmapped renders as the space cell. Tokenamp only ever emits characters from this set,
/// so `sanitize` is the single chokepoint that guarantees it.
public final class BitmapFont {

    public static let glyphWidth = SkinFontSpec.glyphWidth
    public static let glyphHeight = SkinFontSpec.glyphHeight

    private unowned let skin: Skin
    private var cache: [Character: CGImage?] = [:]

    /// character -> (row, col) in text.bmp
    public static let cells: [Character: (row: Int, col: Int)] = {
        var map: [Character: (row: Int, col: Int)] = [:]
        for (r, row) in SkinFontSpec.rows.enumerated() {
            for (c, ch) in row.enumerated() where c < SkinFontSpec.columns {
                if map[ch] == nil { map[ch] = (r, c) }
            }
        }
        map[" "] = (SkinFontSpec.spaceCell.row, SkinFontSpec.spaceCell.col)
        return map
    }()

    /// Every character the classic font can draw.
    public static let charset: Set<Character> = Set(cells.keys)

    init(skin: Skin) { self.skin = skin }

    public static func cell(for character: Character) -> (row: Int, col: Int) {
        if let hit = cells[character] { return hit }
        // Lower case folds to upper case.
        let upper = String(character).uppercased()
        if upper.count == 1, let c = upper.first, let hit = cells[c] { return hit }
        return (SkinFontSpec.spaceCell.row, SkinFontSpec.spaceCell.col)
    }

    public static func rect(for character: Character) -> SpriteRect {
        let cell = self.cell(for: character)
        return SpriteRect(cell.col * glyphWidth, cell.row * glyphHeight, glyphWidth, glyphHeight)
    }

    /// Replace anything the font cannot draw, and upper-case the rest.
    public static func sanitize(_ s: String) -> String {
        var out = String()
        out.reserveCapacity(s.count)
        for ch in s.uppercased() {
            if charset.contains(ch) { out.append(ch) } else { out.append(" ") }
        }
        return out
    }

    public func glyph(_ character: Character) -> CGImage? {
        if let hit = cache[character] { return hit }
        let img = skin.crop(.text, BitmapFont.rect(for: character))
        cache[character] = img
        return img
    }

    public static func width(of s: String) -> Int { s.count * glyphWidth }
}
