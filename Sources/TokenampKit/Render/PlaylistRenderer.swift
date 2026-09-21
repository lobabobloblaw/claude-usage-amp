import CoreGraphics
import Foundation
import UsageModel

/// Draws the resizable "Sessions" window (SPEC 2.4): a frame assembled from the pledit.bmp
/// pieces plus rows set in the skin's own bitmap typeface (SPEC 3.2, amendment A1).
public enum PlaylistRenderer {

    /// Gap the right-aligned value column keeps from the truncated left text (SPEC 3.2).
    public static let valueGap = 4
    /// Left/right inset of the text inside the list area.
    public static let textInset = 3

    /// How many rows fit in a window of this height, at a given row pitch.
    public static func visibleRows(height: Int, rowHeight: Int = Layout.Playlist.rowHeight) -> Int {
        let L = Layout.Playlist.self
        return max(0, (height - L.titleHeight - L.bottomHeight) / max(1, rowHeight))
    }

    public static func listRect(width: Int, height: Int) -> SpriteRect {
        let L = Layout.Playlist.self
        return SpriteRect(L.leftWidth, L.titleHeight,
                          max(0, width - L.leftWidth - L.rightWidth),
                          max(0, height - L.titleHeight - L.bottomHeight))
    }

    public static func draw(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState) {
        let w = max(Layout.Playlist.minSize.w, state.playlistWidth)
        let h = max(Layout.Playlist.minSize.h, state.playlistHeight)
        let selected = state.playlistIsKey

        drawFrame(c, skin: skin, width: w, height: h, selected: selected)
        drawRows(c, skin: skin, snapshot: snapshot, state: state, width: w, height: h)
        drawFooter(c, skin: skin, snapshot: snapshot, state: state, width: w, height: h)
        drawScrollHandle(c, skin: skin, state: state, snapshot: snapshot, width: w, height: h)

        if state.isPressed(.plClose) {
            c.draw(skin.image(Spr.PLAYLIST_CLOSE_SELECTED),
                   at: SpriteRect(w + Layout.Playlist.closeButtonFromTopRight.x,
                                  Layout.Playlist.closeButtonFromTopRight.y, 9, 9))
        }
    }

    // MARK: - Frame

    private static func drawFrame(_ c: SkinCanvas, skin: Skin, width w: Int, height h: Int, selected: Bool) {
        let L = Layout.Playlist.self
        let topLeft = skin.image(selected ? Spr.PLAYLIST_TOP_LEFT_SELECTED : Spr.PLAYLIST_TOP_LEFT_CORNER)
        let topTile = skin.image(selected ? Spr.PLAYLIST_TOP_TILE_SELECTED : Spr.PLAYLIST_TOP_TILE)
        let title = skin.image(selected ? Spr.PLAYLIST_TITLE_BAR_SELECTED : Spr.PLAYLIST_TITLE_BAR)
        let topRight = skin.image(selected ? Spr.PLAYLIST_TOP_RIGHT_CORNER_SELECTED : Spr.PLAYLIST_TOP_RIGHT_CORNER)

        // Tile the whole top edge first, then stamp the corners and the centred title piece.
        c.tileH(topTile, from: 0, to: w, y: 0)
        c.draw(topLeft, at: 0, 0)
        if let topRight { c.draw(topRight, at: w - topRight.width, 0) }
        if let title { c.draw(title, at: (w - title.width) / 2, 0) }

        let midTop = L.titleHeight
        let midBottom = h - L.bottomHeight
        c.tileV(skin.image(Spr.PLAYLIST_LEFT_TILE), from: midTop, to: midBottom, x: 0)
        if let right = skin.image(Spr.PLAYLIST_RIGHT_TILE) {
            c.tileV(right, from: midTop, to: midBottom, x: w - right.width)
        }

        let bottomY = h - L.bottomHeight
        c.tileH(skin.image(Spr.PLAYLIST_BOTTOM_TILE), from: 0, to: w, y: bottomY)
        c.draw(skin.image(Spr.PLAYLIST_BOTTOM_LEFT_CORNER), at: 0, bottomY)
        if let br = skin.image(Spr.PLAYLIST_BOTTOM_RIGHT_CORNER) {
            c.draw(br, at: w - br.width, bottomY)
        }
    }

    // MARK: - Rows

    private static func drawRows(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState,
                                 width w: Int, height h: Int) {
        let area = listRect(width: w, height: h)
        let colours = skin.pledit
        c.fill(area, colours.normalBG)
        guard area.h > 0, area.w > 0 else { return }

        let rows = snapshot.sessionsToday
        let rowHeight = skin.playlistRowHeight
        let capacity = visibleRows(height: h, rowHeight: rowHeight)
        let first = min(max(0, state.playlistScroll), max(0, rows.count - 1))
        let font = skin.playlistFont

        c.save()
        c.clip(to: area)
        for slot in 0..<capacity {
            let index = first + slot
            guard index < rows.count else { break }
            let row = rows[index]
            let y = area.y + slot * rowHeight
            if state.playlistSelection == index {
                c.fill(SpriteRect(area.x, y, area.w, rowHeight), colours.selectedBG)
            }
            let colour = row.isActive ? colours.current : colours.normal
            let left = "\(index + 1). \(row.project) - \(row.model)"
            let right = state.playlistShowsCost
                ? NumberFormatting.money(row.costUSD)
                : NumberFormatting.abbreviated(Double(row.tokens.total))

            if let font {
                let glyphY = y + font.offsetY
                let value = PlaylistFont.sanitize(right)
                let valueWidth = font.measure(value)
                font.draw(value, on: c, x: area.x + area.w - textInset - valueWidth, y: glyphY, tint: colour)
                let budget = area.w - 2 * textInset - valueWidth - valueGap
                let text = font.truncate(PlaylistFont.sanitize(left), maxWidth: budget)
                font.draw(text, on: c, x: area.x + textInset, y: glyphY, tint: colour)
            } else {
                // Last resort (a development checkout with no Base skin): the classic 5x6 font.
                // Still bitmap, still nearest-neighbour - never a system font.
                let glyphY = y + max(0, (rowHeight - BitmapFont.glyphHeight) / 2)
                let value = BitmapFont.sanitize(right)
                let valueWidth = BitmapFont.width(of: value)
                c.text(value, font: skin.font, x: area.x + area.w - textInset - valueWidth, y: glyphY)
                let budget = max(0, area.w - 2 * textInset - valueWidth - valueGap)
                c.text(BitmapFont.sanitize(left), font: skin.font, x: area.x + textInset, y: glyphY,
                       maxGlyphs: budget / BitmapFont.glyphWidth)
            }
        }
        c.restore()
    }

    // MARK: - Footer

    private static func drawFooter(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState,
                                   width w: Int, height h: Int) {
        let L = Layout.Playlist.self
        let font = skin.font
        let info = "\(snapshot.sessionsToday.count) SESS  " + NumberFormatting.money(snapshot.today.costUSD)
        c.text(info, font: font, x: w + L.runningInfoFromBottomRight.a, y: h + L.runningInfoFromBottomRight.b)

        let hero = HeroTrack.hero(in: snapshot, index: state.heroIndex)
        let readout = TimeFormatting.readout(hero: hero, mode: state.timeMode, now: state.now)
        let g = Array(readout.glyphs)
        // Same reading as the main window's digits, minus sign included.
        let sign = readout.minus ? "-" : " "
        let mini = g.count == 4 ? "\(sign)\(g[0])\(g[1]):\(g[2])\(g[3])" : " --:--"
        c.text(mini, font: font, x: w + L.miniTimeFromBottomRight.a, y: h + L.miniTimeFromBottomRight.b)
    }

    private static func drawScrollHandle(_ c: SkinCanvas, skin: Skin, state: ViewState, snapshot: UsageSnapshot,
                                         width w: Int, height h: Int) {
        let L = Layout.Playlist.self
        guard let handle = skin.image(state.isPressed(.plScroll) ? Spr.PLAYLIST_SCROLL_HANDLE_SELECTED
                                                                 : Spr.PLAYLIST_SCROLL_HANDLE) else { return }
        let track = h - L.titleHeight - L.bottomHeight - handle.height
        guard track > 0 else { return }
        let maxScroll = max(0, snapshot.sessionsToday.count
                            - visibleRows(height: h, rowHeight: skin.playlistRowHeight))
        let frac = maxScroll > 0 ? Double(min(state.playlistScroll, maxScroll)) / Double(maxScroll) : 0
        let y = L.titleHeight + Int((frac * Double(track)).rounded())
        c.draw(handle, at: w + L.scrollHandleFromRight, y)
    }

    // MARK: - Hit regions

    public static func regions(width w: Int, height h: Int) -> [HitRegion] {
        let L = Layout.Playlist.self
        let area = listRect(width: w, height: h)
        return [
            HitRegion(.plClose, SpriteRect(w + L.closeButtonFromTopRight.x, L.closeButtonFromTopRight.y, 9, 9)),
            HitRegion(.plScroll, SpriteRect(w + L.scrollHandleFromRight, L.titleHeight, 8,
                                            max(1, h - L.titleHeight - L.bottomHeight)), showsPressed: false),
            HitRegion(.plList, area, showsPressed: false),
            HitRegion(.plResize, SpriteRect(w - 20, h - 20, 20, 20), showsPressed: false),
            HitRegion(.plTitleBar, SpriteRect(0, 0, w, L.titleHeight), showsPressed: false, dragsWindow: true),
        ]
    }

    /// Which row index a click at `point` (skin pixels) lands on, or nil.
    public static func rowIndex(at point: CGPoint, width w: Int, height h: Int, scroll: Int, count: Int,
                                rowHeight: Int = Layout.Playlist.rowHeight) -> Int? {
        let area = listRect(width: w, height: h)
        guard area.contains(point) else { return nil }
        let slot = Int(point.y - CGFloat(area.y)) / max(1, rowHeight)
        let index = scroll + slot
        return index < count ? index : nil
    }

    /// Snap a proposed height onto the 29 px step grid, never below the minimum (SPEC 2.4).
    public static func snapHeight(_ proposed: Int) -> Int {
        let L = Layout.Playlist.self
        let step = L.resizeStep.h
        let minH = L.minSize.h
        let steps = max(0, Int((Double(proposed - minH) / Double(step)).rounded()))
        return minH + steps * step
    }

    /// Width snaps to 25 px steps; Tokenamp keeps the default width but the arithmetic is here.
    public static func snapWidth(_ proposed: Int) -> Int {
        let L = Layout.Playlist.self
        let step = L.resizeStep.w
        let minW = L.minSize.w
        let steps = max(0, Int((Double(proposed - minW) / Double(step)).rounded()))
        return minW + steps * step
    }
}
