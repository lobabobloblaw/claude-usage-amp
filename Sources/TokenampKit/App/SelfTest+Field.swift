import CoreGraphics
import Foundation
import UsageModel

/// Token Flow's pixel-level pieces (SPEC 2.9, 3.3): whole-pixel beam deposits, the hard-ink label
/// face, label fitting and layout, the STRATA staircase, and the small policies around them.
extension SelfTest {

    static func tokenFlowPixels(_ c: Checker) {
        c.section("token flow pixels")
        fieldDeposits(c)
        fieldLabelFace(c)
        fieldLabelFitting(c)
        fieldLabelLayout(c)
        fieldStaircase(c)
        fieldPolicies(c)
    }

    // MARK: - Deposits

    /// A field whose next deposits land at full settled strength (gain 1).
    private static func freshField(_ w: Int, _ h: Int) -> PhosphorField {
        let f = PhosphorField(width: w, height: h)
        f.decay(dt: 1_000, persistence: 1)
        return f
    }

    private static func lit(_ f: PhosphorField, _ ghost: Bool = false) -> [(x: Int, y: Int, e: Double)] {
        var out: [(Int, Int, Double)] = []
        for y in 0..<f.height {
            for x in 0..<f.width {
                let e = ghost ? f.ghostAt(x, y) : f.beamAt(x, y)
                if e > 0 { out.append((x, y, e)) }
            }
        }
        return out
    }

    private static func fieldDeposits(_ c: Checker) {
        let dot = freshField(10, 10)
        dot.dot(3.4, 5.6, 12)
        let d = lit(dot)
        c.check("a dot lands in exactly one pixel", d.count == 1 && d.first?.x == 3 && d.first?.y == 6)

        let half = freshField(12, 8)
        half.segment(1, 2.5, 9, 2.5, 6)
        c.check("a line between two rows lights one row, not two",
                Set(lit(half).map { $0.y }).count == 1)

        let diag = freshField(12, 10)
        diag.segment(0.3, 0.2, 9.1, 6.7, 6)
        let px = lit(diag)
        let columns = Dictionary(grouping: px, by: { $0.x })
        c.check("a shallow diagonal has one pixel in every column it crosses",
                (0...9).allSatisfy { columns[$0]?.count == 1 } && px.count == 10)
        let ys = (0...9).compactMap { columns[$0]?.first?.y }
        c.check("and no gaps between them",
                ys.count == 10 && zip(ys, ys.dropFirst()).allSatisfy { abs($0 - $1) <= 1 })
        let es = px.map { $0.e }
        c.check("every pixel of one pass carries the same energy",
                (es.max() ?? 0) > 0 && abs((es.max() ?? 0) - (es.min() ?? 0)) < 1e-12)

        let steep = freshField(10, 20)
        steep.segment(2.2, 0.4, 7.6, 18.9, 4)
        let rows = Dictionary(grouping: lit(steep), by: { $0.y })
        c.check("a steep line has one pixel in every row", (0...19).allSatisfy { rows[$0]?.count == 1 })

        // Thin: on a simple curve every lit pixel touches at most two others.
        func neighbours(_ set: Set<Int>, _ w: Int, _ x: Int, _ y: Int) -> Int {
            var n = 0
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                if set.contains((y + dy) * w + x + dx) { n += 1 }
            } }
            return n
        }
        let ring = freshField(40, 40)
        ring.arc(centre: CGPoint(x: 20.3, y: 19.6), radius: 11.4, from: 0, to: 2 * .pi, 5)
        let rp = lit(ring)
        let rs = Set(rp.map { $0.y * 40 + $0.x })
        c.check("a circle is one pixel thick all the way round",
                !rp.isEmpty && rp.allSatisfy { neighbours(rs, 40, $0.x, $0.y) == 2 })
        let xs = rp.map { $0.x }, ry = rp.map { $0.y }
        c.check("and symmetric about its centre pixel",
                (xs.max() ?? 0) - 20 == 20 - (xs.min() ?? 0) && (ry.max() ?? 0) - 20 == 20 - (ry.min() ?? 0))

        let partial = freshField(40, 40)
        partial.arc(centre: CGPoint(x: 20, y: 20), radius: 11, from: -.pi / 2, to: 0, 5)
        c.check("a quarter arc lies on the pixels of the full ring",
                !lit(partial).isEmpty
                    && lit(partial).allSatisfy { rs.contains($0.y * 40 + $0.x) && $0.x >= 20 && $0.y <= 20 })

        let s = freshField(60, 40)
        s.curve([CGPoint(x: 3, y: 30), CGPoint(x: 20, y: 5), CGPoint(x: 38, y: 34), CGPoint(x: 56, y: 8)], 3)
        let sp = lit(s)
        let ss = Set(sp.map { $0.y * 60 + $0.x })
        c.check("a curve has no doubled-up corners",
                !sp.isEmpty && sp.allSatisfy { (1...2).contains(neighbours(ss, 60, $0.x, $0.y)) })

        // A polyline lights its joints once, where two separate segments would light them twice.
        let joined = freshField(20, 10)
        joined.polyline([CGPoint(x: 1, y: 5), CGPoint(x: 8, y: 5), CGPoint(x: 15, y: 5)], 4)
        let je = lit(joined).map { $0.e }
        c.check("a polyline lights each joint once",
                je.count == 15 && abs((je.max() ?? 0) - (je.min() ?? 1)) < 1e-12)

        // Settling a still picture in one step lands where forty-eight frames would.
        let now = DemoUsageProvider.referenceDate
        let snap = DemoUsageProvider(frozenAt: now).snapshot
        let mods = FieldModulators(snapshot: snap, now: now)
        let quick = PhosphorField(width: 120, height: 90)
        FieldRenderer.settle(into: quick, snapshot: snap, mode: .strata, span: .minutes, now: now)
        let slow = PhosphorField(width: 120, height: 90)
        let tail = mods.tail(for: .strata)
        let dt = max(1.0 / 30, tail * 2.2 * 6 / 48)
        for i in 0..<48 {
            slow.decay(dt: dt, persistence: tail)
            _ = FieldGeometry.draw(.strata, into: slow, snapshot: snap, mods: mods, span: .minutes,
                                   flows: [:], t: Double(i) * dt, now: now)
        }
        FieldGeometry.drawGraticule(slow, .strata, mods)
        let a = quick.beam, b = slow.beam, ga = quick.ghost, gb = slow.ghost
        let worst = zip(a, b).map { abs($0 - $1) }.max() ?? 1
        let worstGhost = zip(ga, gb).map { abs($0 - $1) }.max() ?? 1
        c.check("a still configuration settles in one step to the frame-by-frame result",
                a.contains { $0 > 0.02 } && worst < 1e-9 && worstGhost < 1e-9)
    }

    // MARK: - Hard-ink face

    /// A 16x6 sheet of 4x4 cells where 'A' has one pixel at each of a few coverages.
    private static func syntheticFont() -> PlaylistFont? {
        let cw = 4, ch = 4, w = cw * 16, h = ch * 6
        var px = [UInt8](repeating: 0, count: w * h * 4)
        func set(_ cell: Int, _ x: Int, _ y: Int, _ v: UInt8) {
            let gx = (cell % 16) * cw + x, gy = (cell / 16) * ch + y
            let i = (gy * w + gx) * 4
            px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255
        }
        let a = Int(Character("A").asciiValue!) - 32
        set(a, 1, 1, 255); set(a, 2, 1, 128); set(a, 1, 2, 127); set(a, 2, 2, 40)
        set(a, 0, 3, 90)                                  // a halo column left of the ink
        let e = PlaylistFont.ellipsisCell
        set(e, 0, 3, 255); set(e, 2, 3, 255)
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        return PlaylistFont(sheet: image, metrics: nil)
    }

    private static func fieldLabelFace(_ c: Checker) {
        guard let font = syntheticFont() else {
            c.check("synthetic plfont loads", false)
            return
        }
        let a = Int(Character("A").asciiValue!) - 32
        c.check("full coverage is ink", font.isHardInk(cell: a, x: 1, y: 1))
        c.check("half coverage is ink", font.isHardInk(cell: a, x: 2, y: 1))
        c.check("just under half is not", !font.isHardInk(cell: a, x: 1, y: 2))
        c.check("a faint halo is not", !font.isHardInk(cell: a, x: 0, y: 3) && !font.isHardInk(cell: a, x: 2, y: 2))
        var pixels: [String] = []
        font.forEachHardInkPixel("A") { x, y in pixels.append("\(x),\(y)") }
        c.equal("a hard glyph lights only its ink, from the pen", pixels, ["0,1", "1,1"])
        c.equal("its ink box", font.hardInkBox("A"), PlaylistFont.InkBox(x: 0, y: 1, w: 2, h: 1))
        c.equal("the hard width is the width the face already measures",
                font.hardInkBox("AA")?.w, font.measure("AA"))
        c.check("a sheet with a real ellipsis cell says so", font.hasEllipsis)

        // The real faces: each must still give legible, solid glyphs at the cut.
        for name in ["Base"] {
            guard let pf = Skin.base.playlistFont else { continue }
            let box = pf.hardInkBox("CLAUDE-USAGE")
            c.check("\(name) plfont sets a label at the cut", (box?.w ?? 0) > 20 && pf.capRows.height >= 5)
        }
    }

    // MARK: - Label fitting

    private static func fieldLabelFitting(_ c: Checker) {
        let m = FieldLabelMetrics.classic
        let long = "CLAUDE-USAGE-AMP"
        let cut = m.fit(long, maxWidth: 50)
        c.check("a long name is cut to fit", cut.map { m.width($0) <= 50 } ?? false)
        c.check("with the ellipsis", cut?.hasSuffix("\u{2026}") ?? false)
        c.check("never on a separator", !(cut?.dropLast().last.map { " -._".contains($0) } ?? true))
        c.equal("a name that fits is whole", m.fit(long, maxWidth: 200), long)

        let bare = FieldLabelMetrics(width: { $0.count * 6 }, height: 7, ellipsis: nil)
        let bareCut = bare.fit("STOREFRONT-CHECKOUT", maxWidth: 70)
        c.check("without an ellipsis glyph the cut is bare and still clean",
                bareCut.map { !$0.contains("\u{2026}") && !" -.".contains($0.last!) && $0.count * 6 <= 70 } ?? false)

        c.equal("a model name is whole where it fits",
                FieldGeometry.modelNames("FABLE 5.1", metrics: m, maxWidth: 64), ["FABLE 5.1", "FABLE"])
        c.equal("and loses its version cleanly where it does not",
                FieldGeometry.modelNames("HAIKU 4.5", metrics: m, maxWidth: 30), ["HAIKU"])
        var dangling = false
        for name in ["FABLE 5.1", "HAIKU 4.5", "SONNET 4.5", "OPUS 5", "CLAUDE-3-5-SONNET"] {
            for width in stride(from: 12, through: 80, by: 4) {
                for text in FieldGeometry.modelNames(name, metrics: m, maxWidth: width)
                where text.hasSuffix(".") || text.hasSuffix(".\u{2026}") || m.width(text) > width {
                    _ = text
                    dangling = true
                }
            }
        }
        c.check("no model label ends on a dangling period or overflows", !dangling)
    }

    // MARK: - Label layout

    private static func fieldLabelLayout(_ c: Checker) {
        let m = FieldLabelMetrics.classic
        var placer = LabelPlacer(width: 120, height: 80, metrics: m)
        let hub = CGPoint(x: 60, y: 40)
        let a = CGPoint(x: 50, y: 30), b = CGPoint(x: 58, y: 31)
        placer.avoid(hub, radius: 4)
        placer.avoid(a, radius: 3)
        placer.avoid(b, radius: 3)
        let first = placer.place(["NODE-A"], near: a, radius: 3, from: hub, faint: false)
        let second = placer.place(["NODE-B"], near: b, radius: 3, from: hub, faint: false)
        c.check("the first label goes on its preferred side", first != nil)
        c.check("a crowded neighbour is nudged to another side, not stacked on it",
                second != nil && (second.map { $0.x != first?.x || $0.y != first?.y } ?? false))
        let boxes = placer.placed
        var overlap = false
        for i in 0..<boxes.count { for j in (i + 1)..<boxes.count where boxes[i].intersects(boxes[j]) { overlap = true } }
        c.check("placed labels never overlap", !overlap)
        c.check("nor cover a node",
                boxes.allSatisfy { box in placer.obstacles.allSatisfy { !box.touches(circle: $0.centre, radius: $0.radius) } })
        var full = LabelPlacer(width: 40, height: 20, metrics: m)
        full.avoid(CGPoint(x: 20, y: 10), radius: 9)
        c.check("a label with nowhere to go is left out",
                full.place(["A-VERY-LONG-NAME"], near: CGPoint(x: 20, y: 10), radius: 9,
                           from: CGPoint(x: 0, y: 0), faint: true) == nil)

        // The connectome itself, with the real face, at the default and the smallest size.
        let now = DemoUsageProvider.referenceDate
        let snap = DemoUsageProvider(frozenAt: now).snapshot
        let mods = FieldModulators(snapshot: snap, now: now)
        let metrics = FieldRenderer.labelMetrics(for: Skin.base)
        for (w, h) in [(Layout.Field.defaultSize.w, Layout.Field.defaultSize.h),
                       (Layout.Field.minSize.w, Layout.Field.minSize.h), (500, 348)] {
            let well = FieldRenderer.canvasRect(width: w, height: h)
            let f = PhosphorField(width: well.w, height: well.h)
            f.decay(dt: 1, persistence: 1)
            let labels = FieldGeometry.draw(.web, into: f, snapshot: snap, mods: mods, span: .minutes,
                                            flows: [:], t: 0, now: now, metrics: metrics)
            let rects = labels.map { LabelPlacer.Box(x: $0.x - 1, y: $0.y - 1,
                                                     w: metrics.width($0.text) + 2, h: metrics.height + 2) }
            var clash = false
            for i in 0..<rects.count { for j in (i + 1)..<rects.count where rects[i].intersects(rects[j]) { clash = true } }
            c.check("web \(w)x\(h): labels do not overlap", !labels.isEmpty && !clash)
            c.check("web \(w)x\(h): labels stay in the well",
                    rects.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.x + $0.w <= well.w && $0.y + $0.h <= well.h })
            c.check("web \(w)x\(h): no label ends on a dangling period",
                    labels.allSatisfy { !$0.text.hasSuffix(".") })
        }
    }

    // MARK: - Staircase

    private static func fieldStaircase(_ c: Checker) {
        let now = DemoUsageProvider.referenceDate
        var minutes: [UsageBucket] = []
        for i in 0..<60 {
            let heavy = i % 2 == 0
            minutes.append(UsageBucket(start: now.addingTimeInterval(Double(i - 60) * 60), duration: 60,
                                       tokens: TokenCounts(input: heavy ? 90_000 : 0, output: heavy ? 40_000 : 0,
                                                           cacheWrite: heavy ? 50_000 : 0,
                                                           cacheRead: heavy ? 4_000_000 : 0)))
        }
        let snap = UsageSnapshot(generatedAt: now, minutes: minutes, lastEventAt: now)
        let mods = FieldModulators(snapshot: snap, now: now)
        let f = PhosphorField(width: 200, height: 120)
        f.decay(dt: 1, persistence: 1)
        _ = FieldGeometry.drawStrata(f, snap, mods, .minutes, now)
        let base = f.height - 10
        let beam = lit(f), ghost = lit(f, true)
        c.check("the ledger draws", !beam.isEmpty)
        c.check("no step dips below the baseline", beam.allSatisfy { $0.y <= base } && ghost.allSatisfy { $0.y <= base })
        // Every riser top is the same height here, so nothing may stand above it.
        let top = beam.map { $0.y }.min() ?? 0
        let risers = beam.filter { $0.y == top }.count
        c.check("no hook over a riser: the tallest row is the flat tops themselves", risers >= 30)
        c.check("the staircase is square: every point is a corner or on a straight run",
                FieldGeometry.staircase([CGPoint(x: 0, y: 5), CGPoint(x: 4, y: 1), CGPoint(x: 8, y: 5)])
                    == [CGPoint(x: 0, y: 5), CGPoint(x: 4, y: 5), CGPoint(x: 4, y: 1),
                        CGPoint(x: 8, y: 1), CGPoint(x: 8, y: 5)])
    }

    // MARK: - Policies

    private static func fieldPolicies(_ c: Checker) {
        // Faint labels stay legible on paper as well as on a dark well.
        let bookcloth = VisColors(rgb: [
            (240, 238, 230), (221, 216, 196), (122, 59, 38), (133, 64, 41), (145, 69, 44),
            (156, 74, 47), (168, 81, 51), (181, 88, 56), (193, 95, 60), (201, 103, 69),
            (209, 111, 78), (217, 119, 87), (215, 133, 100), (214, 148, 114), (212, 162, 127),
            (220, 181, 147), (227, 200, 168), (235, 219, 188), (38, 38, 36), (61, 61, 58),
            (94, 93, 89), (135, 134, 127), (176, 174, 165), (38, 38, 36),
        ])
        let dim = FieldRenderer.dimTint(bookcloth)
        c.check("a faint label on a light skin is clearly legible",
                FieldRenderer.contrast(dim, bookcloth.rgb[0]) >= FieldRenderer.faintContrast)
        let base = Skin.base.visColors
        c.check("a dark skin keeps its mid-ramp faint tint",
                FieldRenderer.dimTint(base) == base.rgb[12]
                    || FieldRenderer.contrast(base.rgb[12], base.rgb[0]) < FieldRenderer.faintContrast)

        // A banded ramp: a line's hue is its level's, so a dim tail cannot fall into another band.
        c.equal("hue comes from the line's level", PhosphorField.rampIndex(level: 1, hotShift: 0), 2)
        c.equal("and a quiet line sits at the dim end", PhosphorField.rampIndex(level: 0, hotShift: 0), 17)

        // The wheel: one step a notch; one step a swipe, however long, and none from momentum.
        var wheel = ScrollStepper()
        let notches = (0..<3).map { _ in
            wheel.feed(.init(delta: 1, precise: false, began: false, ended: false, momentum: false))
        }
        c.equal("a wheel steps once per notch", notches, [1, 1, 1])
        var pad = ScrollStepper()
        var steps = pad.feed(.init(delta: 4, precise: true, began: true, ended: false, momentum: false))
        for _ in 0..<30 { steps += pad.feed(.init(delta: 6, precise: true, began: false, ended: false, momentum: false)) }
        steps += pad.feed(.init(delta: 0, precise: true, began: false, ended: true, momentum: false))
        for _ in 0..<40 { steps += pad.feed(.init(delta: 9, precise: true, began: false, ended: false, momentum: true)) }
        c.equal("a long swipe and its momentum step once", steps, 1)
        var nudge = ScrollStepper()
        let tiny = nudge.feed(.init(delta: 5, precise: true, began: true, ended: false, momentum: false))
            + nudge.feed(.init(delta: 0, precise: true, began: false, ended: true, momentum: false))
        c.equal("a brush of the trackpad does not step", tiny, 0)
        let back = nudge.feed(.init(delta: -30, precise: true, began: true, ended: false, momentum: false))
        c.equal("the next swipe steps again, its own way", back, -1)

        c.equal("the window stops growing at its ceiling", FieldRenderer.snapWidth(5_000), FieldRenderer.maxSize.w)
        c.equal("on the resize grid", (FieldRenderer.maxSize.h - Layout.Field.minSize.h) % Layout.Field.resizeStep.h, 0)

        // The live window bakes labels into the frame; that has to be exactly what drawing them
        // over the frame gives.
        let now = DemoUsageProvider.referenceDate
        let snap = DemoUsageProvider(frozenAt: now).snapshot
        let skin = Skin.base
        let w = Layout.Field.defaultSize.w, h = Layout.Field.defaultSize.h
        let well = FieldRenderer.canvasRect(width: w, height: h)
        let field = PhosphorField(width: well.w, height: well.h)
        let labels = FieldRenderer.settle(into: field, snapshot: snap, mode: .web, span: .minutes, now: now,
                                          metrics: FieldRenderer.labelMetrics(for: skin))
        let pressure = FieldModulators(snapshot: snap, now: now).pressure
        let plain = field.makeImage(skin: skin, pressure: pressure)
        var baked = false
        let withLabels = field.makeImage(skin: skin, pressure: pressure) { overlay in
            baked = FieldRenderer.bake(labels, skin: skin, into: overlay)
        }
        var state = SnapshotRunner.makeState(snapshot: snap, scale: 1, now: now)
        state.fieldMode = .web
        state.fieldWidth = w
        state.fieldHeight = h
        guard baked, let drawn = SkinCanvas.offscreen(width: w, height: h, scale: 2),
              let bakedCanvas = SkinCanvas.offscreen(width: w, height: h, scale: 2) else {
            c.check("labels bake into the frame", false)
            return
        }
        FieldRenderer.draw(drawn, skin: skin, snapshot: snap, state: state, field: plain, labels: labels)
        FieldRenderer.draw(bakedCanvas, skin: skin, snapshot: snap, state: state, field: withLabels, labels: [])
        c.check("baked labels are pixel for pixel the drawn ones",
                samePixelsField(drawn.makeImage(), bakedCanvas.makeImage()))
    }

    private static func samePixelsField(_ a: CGImage?, _ b: CGImage?) -> Bool {
        guard let a, let b, a.width == b.width, a.height == b.height else { return false }
        func bytes(_ i: CGImage) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: i.width * i.height * 4)
            out.withUnsafeMutableBytes { raw in
                let ctx = CGContext(data: raw.baseAddress, width: i.width, height: i.height, bitsPerComponent: 8,
                                    bytesPerRow: i.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                ctx?.draw(i, in: CGRect(x: 0, y: 0, width: i.width, height: i.height))
            }
            return out
        }
        return bytes(a) == bytes(b)
    }
}
