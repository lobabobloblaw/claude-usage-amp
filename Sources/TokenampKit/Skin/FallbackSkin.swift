import CoreGraphics
import CoreText
import Foundation

/// A procedurally drawn stand-in for the bundled Base skin.
///
/// It exists so that Tokenamp always has *something* behind every sprite: if `Base.wsz` is not on
/// disk (a development checkout, a broken install) or a third-party skin omits a sheet, drawing
/// falls back here instead of leaving holes or crashing. It is deliberately plain - dark chassis,
/// cyan accents, legible glyphs - and is never what the user sees when a real skin is installed.
enum FallbackSkin {

    private static let chassis = rgb(0x1E, 0x24, 0x2B)
    private static let chassisLight = rgb(0x39, 0x44, 0x50)
    private static let chassisDark = rgb(0x11, 0x15, 0x19)
    private static let ink = rgb(0x00, 0xE0, 0xC8)
    private static let inkDim = rgb(0x00, 0x74, 0x68)
    private static let hot = rgb(0xFF, 0x8A, 0x3C)
    private static let paper = rgb(0x0A, 0x0D, 0x10)

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    static func make() -> Skin {
        var sheets: [SheetID: CGImage] = [:]
        for id in SkinSpec.sheetOrder {
            guard let spec = SkinSpec.sheets[id] else { continue }
            if let img = ImageMaker.make(width: spec.width, height: spec.height, { c in paint(id, spec, c) }) {
                sheets[id] = img
            }
        }
        return Skin(name: "Base (built-in)", sourceURL: nil, sheets: sheets,
                    visColors: .fallback, pledit: .fallback, regions: SkinRegions(),
                    warnings: ["no Base.wsz found - using the built-in fallback skin"])
    }

    // MARK: - Per-sheet painting

    private static func paint(_ id: SheetID, _ spec: SheetSpec, _ c: SkinCanvas) {
        c.fill(CGRect(x: 0, y: 0, width: CGFloat(spec.width), height: CGFloat(spec.height)), chassis)
        switch id {
        case .main: paintMainWindow(c)
        case .titlebar: paintTitlebar(c)
        case .cbuttons: paintSpritesGeneric(id, c, label: true)
        case .shufrep: paintSpritesGeneric(id, c, label: true)
        case .posbar: paintPosbar(c)
        case .volume: paintFrames(id, c, wide: true)
        case .balance: paintFrames(id, c, wide: false)
        case .monoster: paintSpritesGeneric(id, c, label: true)
        case .playpaus: paintPlaypaus(c)
        case .numbers, .numsEx: paintDigits(id, c)
        case .text: paintFont(c)
        case .eqmain: paintEQ(c)
        case .pledit: paintPledit(c)
        }
    }

    private static func bevel(_ c: SkinCanvas, _ r: CGRect, raised: Bool = true) {
        let tl = raised ? chassisLight : chassisDark
        let br = raised ? chassisDark : chassisLight
        c.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 1), tl)
        c.fill(CGRect(x: r.minX, y: r.minY, width: 1, height: r.height), tl)
        c.fill(CGRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1), br)
        c.fill(CGRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height), br)
    }

    private static func panel(_ c: SkinCanvas, _ r: SpriteRect, fill: CGColor, raised: Bool = true) {
        c.fill(r.cg, fill)
        bevel(c, r.cg, raised: raised)
    }

    /// Tiny vector caption; only ever used by this stand-in skin.
    ///
    /// This is the one place a system font is allowed, and it is not "vector text in a skinned
    /// window" (SPEC 3): it *bakes* letters into a synthetic skin bitmap at 1x, which is then
    /// nearest-neighbour scaled like any other skin art. Nothing at draw time uses it.
    private static func caption(_ c: SkinCanvas, _ s: String, x: CGFloat, y: CGFloat, size: CGFloat = 7,
                                color: CGColor? = nil) {
        bakeText(c, s, fontName: "Helvetica", size: size, x: x, baselineY: y, color: color ?? ink)
    }

    private static func bakeText(_ c: SkinCanvas, _ s: String, fontName: String, size: CGFloat,
                                 x: CGFloat, baselineY: CGFloat, color: CGColor) {
        guard !s.isEmpty else { return }
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        c.ctx.saveGState()
        c.ctx.setShouldAntialias(true)
        c.ctx.setAllowsAntialiasing(true)
        // Undo the y-flip so glyphs are not mirrored, then put the baseline at the origin.
        c.ctx.translateBy(x: x, y: baselineY)
        c.ctx.scaleBy(x: 1, y: -1)
        c.ctx.textPosition = .zero
        CTLineDraw(line, c.ctx)
        c.ctx.restoreGState()
    }

    // main.bmp: the whole chassis with every baked-in element.
    private static func paintMainWindow(_ c: SkinCanvas) {
        let L = Layout.Main.self
        c.fill(CGRect(x: 0, y: 0, width: 275, height: 116), chassis)
        bevel(c, CGRect(x: 0, y: 0, width: 275, height: 116))
        // display well
        panel(c, SpriteRect(20, 22, 85, 40), fill: paper, raised: false)
        panel(c, SpriteRect(107, 22, 160, 18), fill: paper, raised: false)
        // clutter bar (normal state is baked into main.bmp, as in real skins)
        panel(c, L.clutterBar, fill: chassisDark, raised: false)
        for (letter, r) in L.clutterButtons {
            caption(c, letter, x: CGFloat(r.x) + 1.5, y: CGFloat(r.y + r.h) - 1.5, size: 6, color: inkDim)
        }
        // field captions (SPEC 5.1 - Tokenamp's own labels)
        caption(c, "K/MIN", x: 129, y: 49, size: 6)
        caption(c, "ACTIVE", x: 169, y: 49, size: 6)
        caption(c, "SESSION", x: 108, y: 56, size: 5, color: inkDim)
        caption(c, "WEEK", x: 178, y: 56, size: 5, color: inkDim)
        // gauge wells
        panel(c, L.volume, fill: chassisDark, raised: false)
        panel(c, L.balance, fill: chassisDark, raised: false)
        panel(c, L.posbar, fill: chassisDark, raised: false)
        panel(c, L.visualizer, fill: .black, raised: false)
        c.fill(L.aboutLogo.cg, inkDim)
    }

    private static func paintTitlebar(_ c: SkinCanvas) {
        func bar(_ r: SpriteRect, selected: Bool, title: String) {
            c.fill(r.cg, selected ? chassisLight : chassis)
            bevel(c, r.cg)
            caption(c, title, x: CGFloat(r.x) + 104, y: CGFloat(r.y) + 10, size: 8,
                    color: selected ? ink : inkDim)
        }
        bar(Spr.MAIN_TITLE_BAR_SELECTED.rect, selected: true, title: "TOKENAMP")
        bar(Spr.MAIN_TITLE_BAR.rect, selected: false, title: "TOKENAMP")
        bar(Spr.MAIN_SHADE_BACKGROUND_SELECTED.rect, selected: true, title: "")
        bar(Spr.MAIN_SHADE_BACKGROUND.rect, selected: false, title: "")
        bar(Spr.MAIN_EASTER_EGG_TITLE_BAR_SELECTED.rect, selected: true, title: "TOKENAMP")
        bar(Spr.MAIN_EASTER_EGG_TITLE_BAR.rect, selected: false, title: "TOKENAMP")

        for (ref, glyph, pressed) in [
            (Spr.MAIN_OPTIONS_BUTTON, "=", false), (Spr.MAIN_OPTIONS_BUTTON_DEPRESSED, "=", true),
            (Spr.MAIN_MINIMIZE_BUTTON, "_", false), (Spr.MAIN_MINIMIZE_BUTTON_DEPRESSED, "_", true),
            (Spr.MAIN_CLOSE_BUTTON, "x", false), (Spr.MAIN_CLOSE_BUTTON_DEPRESSED, "x", true),
            (Spr.MAIN_SHADE_BUTTON, "^", false), (Spr.MAIN_SHADE_BUTTON_DEPRESSED, "^", true),
            (Spr.MAIN_SHADE_BUTTON_SELECTED, "v", false), (Spr.MAIN_SHADE_BUTTON_SELECTED_DEPRESSED, "v", true),
        ] {
            panel(c, ref.rect, fill: pressed ? chassisDark : chassis, raised: !pressed)
            caption(c, glyph, x: CGFloat(ref.rect.x) + 2, y: CGFloat(ref.rect.y) + 7, size: 7)
        }

        // shade position bar + its three thumb thirds
        panel(c, Spr.MAIN_SHADE_POSITION_BACKGROUND.rect, fill: paper, raised: false)
        for (ref, col) in [(Spr.MAIN_SHADE_POSITION_THUMB_LEFT, inkDim),
                           (Spr.MAIN_SHADE_POSITION_THUMB, ink),
                           (Spr.MAIN_SHADE_POSITION_THUMB_RIGHT, hot)] {
            c.fill(ref.rect.cg, col)
        }

        // clutter bar columns: normal, disabled, then one column per pressed letter
        let letters = ["O", "A", "I", "D", "V"]
        for col in 0..<7 {
            let x = 304 + col * 8
            let y = col < 2 ? 0 : 44
            let r = SpriteRect(x, y, 8, 43)
            c.fill(r.cg, col == 1 ? chassisDark : chassis)
            bevel(c, r.cg)
            for (i, letter) in letters.enumerated() {
                let pressed = col >= 2 && (col - 2) == i
                let ly = y + 3 + i * 8
                if pressed { c.fill(CGRect(x: CGFloat(x + 1), y: CGFloat(ly), width: 6, height: 7), ink) }
                caption(c, letter, x: CGFloat(x) + 1.5, y: CGFloat(ly) + 6, size: 6,
                        color: pressed ? paper : inkDim)
            }
        }
    }

    private static func paintPosbar(_ c: SkinCanvas) {
        panel(c, Spr.MAIN_POSITION_SLIDER_BACKGROUND.rect, fill: chassisDark, raised: false)
        c.fill(CGRect(x: 2, y: 4, width: 244, height: 2), paper)
        panel(c, Spr.MAIN_POSITION_SLIDER_THUMB.rect, fill: chassisLight)
        panel(c, Spr.MAIN_POSITION_SLIDER_THUMB_SELECTED.rect, fill: ink)
    }

    private static func paintFrames(_ id: SheetID, _ c: SkinCanvas, wide: Bool) {
        guard let spec = SkinSpec.sheets[id], let f = spec.frames else { return }
        for i in 0..<f.count {
            let r = f.rect(i)
            let t = CGFloat(i) / CGFloat(f.count - 1)
            c.fill(r.cg, chassisDark)
            bevel(c, r.cg, raised: false)
            let filled = Int(round(CGFloat(r.w - 4) * t))
            if filled > 0 {
                c.fill(CGRect(x: CGFloat(r.x + 2), y: CGFloat(r.y + 4), width: CGFloat(filled), height: 5),
                       CGColor(srgbRed: t, green: 1 - 0.6 * t, blue: 0.3, alpha: 1))
            }
        }
        let thumbs = wide ? [Spr.MAIN_VOLUME_THUMB, Spr.MAIN_VOLUME_THUMB_SELECTED]
                          : [Spr.MAIN_BALANCE_THUMB, Spr.MAIN_BALANCE_THUMB_SELECTED]
        for (i, t) in thumbs.enumerated() {
            panel(c, t.rect, fill: i == 0 ? chassisLight : ink)
            c.fill(CGRect(x: CGFloat(t.rect.x) + 6, y: CGFloat(t.rect.y) + 1, width: 2, height: 9), paper)
        }
    }

    private static func paintPlaypaus(_ c: SkinCanvas) {
        c.fill(CGRect(x: 0, y: 0, width: 42, height: 9), paper)
        // play triangle
        for i in 0..<5 { c.fill(CGRect(x: CGFloat(2 + i), y: CGFloat(4 - i / 2 - (i > 0 ? 1 : 0)) , width: 1, height: CGFloat(1 + i)), ink) }
        c.fill(CGRect(x: 2, y: 2, width: 1, height: 5), ink)
        c.fill(CGRect(x: 3, y: 3, width: 1, height: 3), ink)
        c.fill(CGRect(x: 4, y: 4, width: 1, height: 1), ink)
        // pause bars
        c.fill(CGRect(x: 11, y: 2, width: 2, height: 5), ink)
        c.fill(CGRect(x: 15, y: 2, width: 2, height: 5), ink)
        // stop square
        c.fill(CGRect(x: 20, y: 2, width: 5, height: 5), ink)
        // work LED off / on
        c.fill(Spr.MAIN_NOT_WORKING_INDICATOR.rect.cg, inkDim)
        c.fill(Spr.MAIN_WORKING_INDICATOR.rect.cg, hot)
    }

    private static func paintDigits(_ id: SheetID, _ c: SkinCanvas) {
        guard let rects = SkinSpec.spriteRects[id] else { return }
        for (name, r) in rects {
            guard r.w >= 5, r.h >= 5 else { continue }
            c.fill(r.cg, paper)
            var glyph: String? = nil
            if name.hasPrefix("DIGIT_"), name.count == 7, let d = name.last, d.isNumber { glyph = String(d) }
            if name.hasSuffix("MINUS") { glyph = "-" }
            if let glyph {
                caption(c, glyph, x: CGFloat(r.x) + 1.5, y: CGFloat(r.y + r.h) - 2, size: 12)
            }
        }
        // legacy minus strips live inside the digit cells
        if id == .numbers {
            c.fill(Spr.MINUS_SIGN.rect.cg, ink)
            c.fill(Spr.NO_MINUS_SIGN.rect.cg, paper)
        }
    }

    private static func paintFont(_ c: SkinCanvas) {
        guard let spec = SkinSpec.sheets[.text] else { return }
        c.fill(CGRect(x: 0, y: 0, width: CGFloat(spec.width), height: CGFloat(spec.height)), paper)
        for (r, row) in SkinFontSpec.rows.enumerated() {
            for (col, ch) in row.enumerated() where col < SkinFontSpec.columns {
                let x = CGFloat(col * SkinFontSpec.glyphWidth)
                let y = CGFloat(r * SkinFontSpec.glyphHeight)
                if ch == " " { continue }
                bakeText(c, String(ch), fontName: "Menlo", size: 6.5, x: x + 0.2, baselineY: y + 5.2, color: ink)
            }
        }
    }

    private static func paintEQ(_ c: SkinCanvas) {
        c.fill(CGRect(x: 0, y: 0, width: 275, height: 116), chassis)
        bevel(c, CGRect(x: 0, y: 0, width: 275, height: 116))
        panel(c, Layout.EQ.graph, fill: paper, raised: false)
        panel(c, Layout.EQ.preampSlider, fill: chassisDark, raised: false)
        let B = Layout.EQ.BandSliders.self
        for i in 0..<B.count {
            panel(c, SpriteRect(B.x0 + i * B.strideX, B.y, B.w, B.h), fill: chassisDark, raised: false)
        }
        caption(c, "WEEK", x: 16, y: 110, size: 6)
        for (i, cap) in ["-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1", "NOW"].enumerated() {
            caption(c, cap, x: CGFloat(B.x0 + i * B.strideX), y: 110, size: 6, color: inkDim)
        }
        for (ref, selected, title) in [
            (Spr.EQ_TITLE_BAR_SELECTED, true, "USAGE EQUALIZER"), (Spr.EQ_TITLE_BAR, false, "USAGE EQUALIZER"),
        ] {
            c.fill(ref.rect.cg, selected ? chassisLight : chassis)
            bevel(c, ref.rect.cg)
            caption(c, title, x: CGFloat(ref.rect.x) + 94, y: CGFloat(ref.rect.y) + 10, size: 8,
                    color: selected ? ink : inkDim)
        }
        for (ref, label, on) in [
            (Spr.EQ_CLOSE_BUTTON, "x", false), (Spr.EQ_CLOSE_BUTTON_ACTIVE, "x", true),
            (Spr.EQ_ON_BUTTON, "ON", false), (Spr.EQ_ON_BUTTON_DEPRESSED, "ON", true),
            (Spr.EQ_ON_BUTTON_SELECTED, "ON", true), (Spr.EQ_ON_BUTTON_SELECTED_DEPRESSED, "ON", true),
            (Spr.EQ_AUTO_BUTTON, "AUTO", false), (Spr.EQ_AUTO_BUTTON_DEPRESSED, "AUTO", true),
            (Spr.EQ_AUTO_BUTTON_SELECTED, "AUTO", true), (Spr.EQ_AUTO_BUTTON_SELECTED_DEPRESSED, "AUTO", true),
            (Spr.EQ_PRESETS_BUTTON, "RANGE", false), (Spr.EQ_PRESETS_BUTTON_SELECTED, "RANGE", true),
        ] {
            panel(c, ref.rect, fill: on ? inkDim : chassis, raised: !on)
            caption(c, label, x: CGFloat(ref.rect.x) + 3, y: CGFloat(ref.rect.y + ref.rect.h) - 3, size: 7,
                    color: on ? paper : ink)
        }
        panel(c, Spr.EQ_SLIDER_THUMB.rect, fill: chassisLight)
        panel(c, Spr.EQ_SLIDER_THUMB_SELECTED.rect, fill: ink)
        // 28 slider wells, bottom (0) to top (27)
        if let f = SkinSpec.sheets[.eqmain]?.frames {
            for i in 0..<f.count {
                let r = f.rect(i)
                c.fill(r.cg, chassisDark)
                bevel(c, r.cg, raised: false)
                c.fill(CGRect(x: CGFloat(r.x + 6), y: CGFloat(r.y + 2), width: 2, height: CGFloat(r.h - 4)), paper)
                let t = CGFloat(i) / CGFloat(f.count - 1)
                let h = CGFloat(r.h - 6) * t
                c.fill(CGRect(x: CGFloat(r.x + 5), y: CGFloat(r.y + r.h - 3) - h, width: 4, height: max(1, h)), ink)
            }
        }
        c.fill(Spr.EQ_GRAPH_BACKGROUND.rect.cg, paper)
        for y in 0..<19 {
            let t = CGFloat(y) / 18
            c.fill(CGRect(x: CGFloat(Spr.EQ_GRAPH_LINE_COLORS.rect.x), y: CGFloat(294 + y), width: 1, height: 1),
                   CGColor(srgbRed: t, green: 1 - t * 0.5, blue: 0.6, alpha: 1))
        }
        c.fill(Spr.EQ_PREAMP_LINE.rect.cg, hot)
    }

    private static func paintPledit(_ c: SkinCanvas) {
        guard let rects = SkinSpec.spriteRects[.pledit] else { return }
        for (name, r) in rects {
            let selected = name.hasSuffix("SELECTED")
            c.fill(r.cg, selected ? chassisLight : chassis)
            bevel(c, r.cg)
            if name.contains("TITLE_BAR") {
                caption(c, "SESSIONS", x: CGFloat(r.x) + 28, y: CGFloat(r.y) + 13, size: 8,
                        color: selected ? ink : inkDim)
            }
            if name.contains("CLOSE") { caption(c, "x", x: CGFloat(r.x) + 2, y: CGFloat(r.y) + 7, size: 7) }
            if name.contains("COLLAPSE") { caption(c, "-", x: CGFloat(r.x) + 2, y: CGFloat(r.y) + 7, size: 7) }
            if name.contains("SCROLL_HANDLE") { c.fill(r.cg, selected ? ink : chassisLight) }
            if name.contains("VISUALIZER") { c.fill(r.cg, paper) }
        }
    }

    // Generic: fill each named sprite with a bevelled panel and its short label.
    private static func paintSpritesGeneric(_ id: SheetID, _ c: SkinCanvas, label: Bool) {
        guard let rects = SkinSpec.spriteRects[id] else { return }
        for (name, r) in rects {
            let pressed = name.hasSuffix("ACTIVE") || name.contains("DEPRESSED")
            let selected = name.contains("SELECTED")
            panel(c, r, fill: pressed ? chassisDark : (selected ? inkDim : chassis), raised: !pressed)
            guard label else { continue }
            let short = shortLabel(name)
            caption(c, short, x: CGFloat(r.x) + 2, y: CGFloat(r.y + r.h) - 4, size: 6,
                    color: pressed ? ink : (selected ? paper : ink))
        }
    }

    private static func shortLabel(_ name: String) -> String {
        var t = name
        for prefix in ["MAIN_", "EQ_", "PLAYLIST_"] where t.hasPrefix(prefix) { t.removeFirst(prefix.count) }
        for suffix in ["_BUTTON_ACTIVE", "_BUTTON_DEPRESSED_SELECTED", "_BUTTON_SELECTED_DEPRESSED",
                       "_BUTTON_DEPRESSED", "_BUTTON_SELECTED", "_BUTTON", "_SELECTED", "_ACTIVE"]
            where t.hasSuffix(suffix) { t.removeLast(suffix.count); break }
        switch t {
        case "PREVIOUS": return "|<"
        case "PLAY": return ">"
        case "PAUSE": return "||"
        case "STOP": return "[]"
        case "NEXT": return ">|"
        case "EJECT": return "^"
        case "SHUFFLE": return "CYCLE"
        case "REPEAT": return "ALERT"
        case "PLAYLIST": return "PL"
        case "MONO": return "LOCAL"
        case "STEREO": return "LIVE"
        default: return String(t.prefix(5))
        }
    }
}
