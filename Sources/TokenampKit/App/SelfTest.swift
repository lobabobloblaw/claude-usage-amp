import CoreGraphics
import Foundation
import UsageModel

/// `Tokenamp --selftest`: assertion-style checks over the pure logic and the skin engine.
/// There is no XCTest on this toolchain, so this is the test suite.
public enum SelfTest {

    // MARK: - Harness

    final class Checker {
        private(set) var passed = 0
        private(set) var failed = 0
        private(set) var skipped = 0
        private var group = ""

        func section(_ name: String) {
            group = name
            print("\n== \(name)")
        }

        func check(_ what: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                passed += 1
            } else {
                failed += 1
                print("  FAIL  \(what)")
            }
        }

        func equal<T: Equatable>(_ what: String, _ actual: @autoclosure () -> T, _ expected: T) {
            let a = actual()
            if a == expected {
                passed += 1
            } else {
                failed += 1
                print("  FAIL  \(what): got \(a), expected \(expected)")
            }
        }

        func close(_ what: String, _ actual: Double, _ expected: Double, _ tolerance: Double = 1e-9) {
            if abs(actual - expected) <= tolerance {
                passed += 1
            } else {
                failed += 1
                print("  FAIL  \(what): got \(actual), expected \(expected) +- \(tolerance)")
            }
        }

        func skip(_ what: String, _ why: String) {
            skipped += 1
            print("  SKIP  \(what) (\(why))")
        }
    }

    public static func run() -> Bool {
        let c = Checker()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenamp-selftest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        generatedTable(c)
        timeFormatting(c)
        numberFormatting(c)
        marquee(c)
        sliders(c)
        visualizer(c)
        eqModel(c)
        docking(c)
        scaleModel(c)
        windowPositions(c, tmp: tmp)
        tokenFlowPixels(c)
        playlistGeometry(c)
        tokenFlow(c)
        fontMap(c)
        playlistFont(c, tmp: tmp)
        textFileParsers(c)
        zipReader(c, tmp: tmp)
        skinLoading(c, tmp: tmp)
        rendering(c)
        uiFixes(c, tmp: tmp)

        print("\n\(c.passed) passed, \(c.failed) failed, \(c.skipped) skipped")
        return c.failed == 0
    }

    // MARK: - Generated sprite table

    private static func generatedTable(_ c: Checker) {
        c.section("sprites.json -> generated table")
        c.equal("main window size", Layout.Main.size, SkinPair(275, 116))
        c.equal("visualizer well", Layout.Main.visualizer, SpriteRect(24, 43, 76, 16))
        c.equal("marquee is 154 px", Layout.Main.marquee.w, 154)
        c.equal("volume travel span", Layout.Main.volumeThumbTravel.span, 51)
        c.equal("balance travel span", Layout.Main.balanceThumbTravel.span, 24)
        c.equal("posbar travel span", Layout.Main.posbarThumbTravel.span, 219)
        c.equal("4 digit cells", Layout.Main.digits.count, 4)
        c.equal("10 EQ bands", Layout.EQ.BandSliders.count, 10)
        c.equal("eqmain frame 0", SkinSpec.sheets[.eqmain]?.frames?.rect(0), SpriteRect(13, 164, 14, 63))
        c.equal("eqmain frame 13", SkinSpec.sheets[.eqmain]?.frames?.rect(13), SpriteRect(208, 164, 14, 63))
        c.equal("eqmain frame 14", SkinSpec.sheets[.eqmain]?.frames?.rect(14), SpriteRect(13, 229, 14, 63))
        c.equal("volume frame 5", SkinSpec.sheets[.volume]?.frames?.rect(5), SpriteRect(0, 75, 68, 13))
        c.equal("balance frame 27", SkinSpec.sheets[.balance]?.frames?.rect(27), SpriteRect(9, 405, 38, 13))
        c.equal("play sprite", Spr.MAIN_PLAY_BUTTON.rect, SpriteRect(23, 0, 23, 18))
        c.check("every sheet has a spec", SheetID.allCases.allSatisfy { SkinSpec.sheets[$0] != nil })
        c.equal("clutter buttons", Layout.Main.clutterButtons.map { $0.0 }, ["O", "A", "I", "D", "V"])
    }

    // MARK: - Time

    private static func timeFormatting(_ c: Checker) {
        c.section("time formatting")
        c.equal("59 s -> MM:SS", TimeFormatting.digits(forInterval: 59), "0059")
        c.equal("90 s -> MM:SS", TimeFormatting.digits(forInterval: 90), "0130")
        c.equal("3599 s -> MM:SS", TimeFormatting.digits(forInterval: 3599), "5959")
        c.equal("3600 s -> HH:MM", TimeFormatting.digits(forInterval: 3600), "0100")
        c.equal("2h47m -> HH:MM", TimeFormatting.digits(forInterval: 2 * 3600 + 47 * 60), "0247")
        c.equal("negative clamps", TimeFormatting.digits(forInterval: -5), "0000")
        c.equal("99h clamp", TimeFormatting.digits(forInterval: 400 * 3600), "9900")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        let now = date("2026-09-20 12:00:00", cal)
        c.equal("today -> H:MM AM/PM",
                TimeFormatting.resetWording(date("2026-09-20 18:50:00", cal), now: now, calendar: cal),
                "6:50 PM")
        c.equal("midnight-ish today",
                TimeFormatting.resetWording(date("2026-09-20 00:05:00", cal), now: now, calendar: cal),
                "12:05 AM")
        c.equal("another day, whole hour",
                TimeFormatting.resetWording(date("2026-09-26 13:00:00", cal), now: now, calendar: cal),
                "SAT 1 PM")
        c.equal("another day, with minutes",
                TimeFormatting.resetWording(date("2026-09-21 13:30:00", cal), now: now, calendar: cal),
                "MON 1:30 PM")
        c.equal("unknown reset", TimeFormatting.resetWording(nil, now: now, calendar: cal), "UNKNOWN")

        c.equal("compact 2h47m", TimeFormatting.compactDuration(2 * 3600 + 47 * 60), "2H47M")
        c.equal("compact 47m", TimeFormatting.compactDuration(47 * 60), "47M")
        c.equal("compact seconds", TimeFormatting.compactDuration(30), "30S")

        // Digit readout modes.
        let limit = LimitGauge(id: "session", kind: .session, title: "SESSION (5H)", percent: 44,
                               resetsAt: now.addingTimeInterval(2 * 3600 + 47 * 60),
                               windowSeconds: 5 * 3600, isActive: true)
        let remaining = TimeFormatting.readout(hero: limit, mode: .remaining, now: now, calendar: cal)
        c.equal("remaining digits", remaining.glyphs, "0247")
        c.check("remaining shows minus", remaining.minus)
        let elapsed = TimeFormatting.readout(hero: limit, mode: .elapsed, now: now, calendar: cal)
        c.equal("elapsed digits", elapsed.glyphs, "0213")
        c.check("elapsed hides minus", !elapsed.minus)
        let wall = TimeFormatting.readout(hero: nil, mode: .remaining, now: now, calendar: cal)
        c.check("no limit -> wall clock", wall.isWallClock && wall.glyphs == "1200" && !wall.minus)
    }

    private static func date(_ s: String, _ cal: Calendar) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)!
    }

    private static func numberFormatting(_ c: Checker) {
        c.section("number formatting")
        c.equal("12", NumberFormatting.abbreviated(12), "12")
        c.equal("1.2K", NumberFormatting.abbreviated(1_234), "1.2K")
        c.equal("12K", NumberFormatting.abbreviated(12_000), "12K")
        c.equal("1.2M", NumberFormatting.abbreviated(1_240_000), "1.2M")
        c.equal("money", NumberFormatting.money(12.4), "$12.40")
        c.equal("big money", NumberFormatting.money(1234), "$1234")
        c.equal("percent", NumberFormatting.percent(41.6), "42%")
    }

    // MARK: - Marquee

    private static func marquee(_ c: Checker) {
        c.section("marquee")
        let snap = DemoUsageProvider(frozenAt: DemoUsageProvider.referenceDate).snapshot
        let text = Marquee.compose(snapshot: snap, heroIndex: 0, isPaused: false, isStopped: false,
                                   now: DemoUsageProvider.referenceDate)
        c.check("non-empty", !text.isEmpty)
        c.check("only classic-font characters", text.allSatisfy { BitmapFont.charset.contains($0) })
        c.check("sanitize is a fixpoint", BitmapFont.sanitize(text) == text)
        c.check("has a separator", text.contains(Marquee.separator))
        c.check("names the hero limit", text.contains("SESSION"))
        c.check("names the plan", text.contains("MAX 20X"))
        c.check("has a burn section", text.contains("BURN"))
        c.check("ends with the separator so the loop is seamless", text.hasSuffix(Marquee.separator))

        c.equal("scroll width", Marquee.scrollWidth("ABC"), 15)
        let glyphs = Marquee.visibleGlyphs(text: "ABCDE", offset: 0, width: 10)
        c.equal("first glyph", glyphs.first?.character, "A")
        c.equal("second glyph x", glyphs.count > 1 ? glyphs[1].x : -1, 5)
        let scrolled = Marquee.visibleGlyphs(text: "ABCDE", offset: 7, width: 10)
        c.equal("sub-pixel offset", scrolled.first?.x, -2)
        c.equal("scrolled first glyph", scrolled.first?.character, "B")
        let wrapped = Marquee.visibleGlyphs(text: "ABCDE", offset: 24, width: 10)
        c.equal("wraps around", wrapped.count >= 3 ? wrapped[1].character : " ", "A")
        let negative = Marquee.visibleGlyphs(text: "ABCDE", offset: -5, width: 10)
        c.equal("negative offset wraps", negative.first?.character, "E")

        // Hover readings stay in the charset too.
        for reading in [Marquee.volumeReading(snap, now: DemoUsageProvider.referenceDate),
                        Marquee.balanceReading(snap, now: DemoUsageProvider.referenceDate),
                        Marquee.posbarReading(snap, heroIndex: 0, now: DemoUsageProvider.referenceDate),
                        Marquee.burnReading(snap),
                        Marquee.activeSessionsReading(snap),
                        Marquee.sourcesReading(snap),
                        Marquee.visualizerReading(),
                        Marquee.eqBandReading(label: "T-3H", tokens: 1_240_000, cost: 4.1)] {
            c.check("reading in charset: \(reading)", reading.allSatisfy { BitmapFont.charset.contains($0) })
        }
        c.equal("EQ band reading shape",
                Marquee.eqBandReading(label: "T-3H", tokens: 1_240_000, cost: 4.1), "T-3H: 1.2M TOK  $4.10")

        let paused = Marquee.statusPhrase(snapshot: snap, isPaused: true, isStopped: false)
        c.equal("paused status", paused, "PAUSED")
        var scanning = snap
        scanning.localStatus = LocalStatus(isScanning: true, filesDone: 41, filesTotal: 323)
        c.equal("scanning status", Marquee.statusPhrase(snapshot: scanning, isPaused: false, isStopped: false),
                "SCANNING 41/323")
        var expired = snap
        expired.liveStatus = .authExpired
        c.equal("auth expired status", Marquee.statusPhrase(snapshot: expired, isPaused: false, isStopped: false),
                "LIVE: AUTH EXPIRED - OPEN CLAUDE CODE")
    }

    // MARK: - Sliders

    private static func sliders(_ c: Checker) {
        c.section("slider maths")
        // SPEC 2.1: volume thumb x = 107 + pct*51/100, frame = round(pct*27/100)
        c.equal("volume 0%", Sliders.thumbX(percent: 0, travel: Layout.Main.volumeThumbTravel), 107)
        c.equal("volume 100%", Sliders.thumbX(percent: 100, travel: Layout.Main.volumeThumbTravel), 158)
        c.equal("volume 50%", Sliders.thumbX(percent: 50, travel: Layout.Main.volumeThumbTravel), 107 + 25)
        c.equal("volume 42%", Sliders.thumbX(percent: 42, travel: Layout.Main.volumeThumbTravel),
                107 + Int(42.0 * 51.0 / 100.0))
        c.equal("volume frame 0%", Sliders.frameIndex(percent: 0), 0)
        c.equal("volume frame 100%", Sliders.frameIndex(percent: 100), 27)
        c.equal("volume frame 50%", Sliders.frameIndex(percent: 50), Int((50.0 * 27.0 / 100.0).rounded()))
        c.equal("clamps above 100", Sliders.frameIndex(percent: 300), 27)
        c.equal("clamps below 0", Sliders.thumbX(percent: -20, travel: Layout.Main.volumeThumbTravel), 107)

        // Balance: 177 + pct*24/100
        c.equal("balance 0%", Sliders.thumbX(percent: 0, travel: Layout.Main.balanceThumbTravel), 177)
        c.equal("balance 100%", Sliders.thumbX(percent: 100, travel: Layout.Main.balanceThumbTravel), 201)

        // Position bar: 0..219 px of travel
        c.equal("posbar 0", Sliders.thumbX(fraction: 0, travel: Layout.Main.posbarThumbTravel), 16)
        c.equal("posbar 1", Sliders.thumbX(fraction: 1, travel: Layout.Main.posbarThumbTravel), 235)
        c.equal("posbar half", Sliders.thumbX(fraction: 0.5, travel: Layout.Main.posbarThumbTravel), 16 + 109)
        c.check("posbar thumb stays inside the well",
                Sliders.thumbX(fraction: 1, travel: Layout.Main.posbarThumbTravel) + 29
                    <= Layout.Main.posbar.x + Layout.Main.posbar.w)
        c.check("volume thumb stays inside the gauge",
                Sliders.thumbX(percent: 100, travel: Layout.Main.volumeThumbTravel) + 14
                    <= Layout.Main.volume.x + Layout.Main.volume.w)

        // EQ sliders: value 1 at the top of the 51 px travel.
        let y = Layout.EQ.BandSliders.y
        c.equal("eq max at top", Sliders.eqThumbY(value: 1, sliderY: y, travel: Layout.EQ.sliderThumbTravelY), y)
        c.equal("eq min at bottom", Sliders.eqThumbY(value: 0, sliderY: y, travel: Layout.EQ.sliderThumbTravelY), y + 51)
        c.check("eq thumb stays inside the well",
                Sliders.eqThumbY(value: 0, sliderY: y, travel: Layout.EQ.sliderThumbTravelY) + 11
                    <= y + Layout.EQ.BandSliders.h)
        c.close("eq value round-trips",
                Sliders.eqValue(forThumbY: Sliders.eqThumbY(value: 0.5, sliderY: y, travel: Layout.EQ.sliderThumbTravelY),
                                sliderY: y, travel: Layout.EQ.sliderThumbTravelY), 0.5, 0.02)

        // Shade mini bar.
        c.equal("shade thumb left third", Sliders.shadePosition(fraction: 0).piece, .left)
        c.equal("shade thumb right third", Sliders.shadePosition(fraction: 1).piece, .right)
        c.equal("shade thumb centre", Sliders.shadePosition(fraction: 0.5).piece, .centre)
        c.check("shade thumb inside the 17 px well",
                Sliders.shadePosition(fraction: 1).x + 3 <= Layout.Shade.position.x + Layout.Shade.position.w)
    }

    // MARK: - Visualizer

    private static func visualizer(_ c: Checker) {
        c.section("visualizer")
        c.equal("19 bars x 4 px fills the 76 px well",
                VisualizerModel.barCount * VisualizerModel.barPitch, Layout.Main.visualizer.w)
        c.equal("4 fine buckets per bar", VisualizerModel.bucketsPerBar, 4)
        c.equal("silence is zero", VisualizerModel.normalize(cost: 0), 0)
        c.check("normalize is monotonic",
                VisualizerModel.normalize(cost: 0.1) < VisualizerModel.normalize(cost: 1.0))
        c.check("normalize clamps at 1", VisualizerModel.normalize(cost: 1000) <= 1)

        let snap = DemoUsageProvider(frozenAt: DemoUsageProvider.referenceDate).snapshot
        let targets = VisualizerModel.targets(snap)
        c.equal("one target per bar", targets.count, 19)
        c.check("targets in range", targets.allSatisfy { $0 >= 0 && $0 <= 1 })
        c.check("demo data actually moves the bars", targets.contains { $0 > 0.05 })

        let settled = VisualizerModel.settled(snap, rows: 16)
        c.check("peaks sit above bars", zip(settled.bars, settled.peaks).allSatisfy { $1 >= $0 })
        c.check("peak caps are 2 rows up where there is a bar",
                zip(settled.bars, settled.peaks).allSatisfy { b, p in
                    b == 0 ? p == 0 : abs(p - min(1, b + 2.0 / 16)) < 1e-9
                })

        let hot = VisualizerModel.hotBars(snap, now: DemoUsageProvider.referenceDate)
        c.check("the newest bar is hot", hot.contains(18))
        c.check("old bars are not hot", !hot.contains(0))

        let scope = VisualizerModel.scope(snap)
        c.equal("one scope sample per fine bucket", scope.count, UsageSnapshot.fineBucketCount)
        c.check("scope stays in range", scope.allSatisfy { $0 >= -1 && $0 <= 1 })

        // The animated model converges on the settled state.
        let model = VisualizerModel()
        for _ in 0..<400 { model.advance(snapshot: snap, now: DemoUsageProvider.referenceDate, dt: 1.0 / 30) }
        let quiet = zip(model.bars, settled.bars).filter { $0.1 < 0.05 }
        c.check("quiet bars converge", quiet.allSatisfy { abs($0.0 - $0.1) < 0.12 })
        c.check("bars stay in range", model.bars.allSatisfy { $0 >= 0 && $0 <= 1 })

        model.silence()
        c.check("stop silences everything", model.bars.allSatisfy { $0 == 0 })

        // An empty snapshot must not trap.
        let empty = UsageSnapshot.empty()
        c.equal("empty snapshot -> zero bars", VisualizerModel.targets(empty).filter { $0 > 0 }.count, 0)
        c.equal("empty snapshot -> flat scope", VisualizerModel.scope(empty).filter { $0 != 0 }.count, 0)
    }

    // MARK: - EQ

    private static func eqModel(_ c: Checker) {
        c.section("EQ model")
        let snap = DemoUsageProvider(frozenAt: DemoUsageProvider.referenceDate).snapshot
        for range in EQRange.allCases {
            for measure in EQMeasure.allCases {
                let bands = EQModel.bands(snap, range: range, measure: measure, relative: true)
                c.equal("\(range.rawValue)/\(measure.rawValue) band count", bands.count, 10)
                c.check("\(range.rawValue)/\(measure.rawValue) levels in range",
                        bands.allSatisfy { $0.level >= 0 && $0.level <= 1 })
            }
        }
        let bands = EQModel.bands(snap, range: .hours, measure: .cost, relative: true)
        c.equal("newest band is NOW", bands.last?.label, "NOW")
        c.equal("oldest band is T-9H", bands.first?.label, "T-9H")
        c.check("relative scaling puts the max at 1", bands.contains { abs($0.level - 1) < 1e-9 })
        let days = EQModel.bands(snap, range: .days, measure: .allTokens, relative: true)
        c.equal("day labels", days.first?.label, "T-9D")
        let minutes = EQModel.bands(snap, range: .minutes, measure: .outputTokens, relative: true)
        c.equal("minute labels", minutes.first?.label, "T-9M")

        // Fixed log scale endpoints (SPEC 2.3).
        c.equal("cost log floor", EQModel.logLevel(0.01, lo: 0.01, hi: 100), 0)
        c.close("cost log ceiling", EQModel.logLevel(100, lo: 0.01, hi: 100), 1)
        c.close("cost log midpoint", EQModel.logLevel(1, lo: 0.01, hi: 100), 0.5, 1e-9)
        c.close("token log midpoint", EQModel.logLevel(316_227.766, lo: 1_000, hi: 100_000_000), 0.5, 1e-4)

        let curve = EQModel.graphCurve(levels: bands.map { $0.level }, width: Layout.EQ.graph.w)
        c.equal("curve spans the graph", curve.count, 113)
        c.check("curve stays in range", curve.allSatisfy { $0 >= 0 && $0 <= 1 })
        c.close("curve starts at the first band", curve.first ?? -1, bands.first?.level ?? -2, 1e-9)
        c.close("curve ends at the last band", curve.last ?? -1, bands.last?.level ?? -2, 1e-9)

        // Preamp = scoped weekly if present.
        c.close("preamp uses the scoped weekly limit", EQModel.preampLevel(snap),
                (snap.limit(.weeklyScoped)?.percent ?? 0) / 100, 1e-9)
        let noScope = UsageSnapshot(generatedAt: Date(), limits: [
            LimitGauge(id: "weekly_all", kind: .weeklyAll, title: "WEEK", percent: 40, resetsAt: nil, windowSeconds: nil),
        ])
        c.close("preamp falls back to weekly-all", EQModel.preampLevel(noScope), 0.4, 1e-9)
        c.equal("preamp with no limits", EQModel.preampLevel(UsageSnapshot.empty()), 0)
    }

    // MARK: - Docking

    private static func docking(_ c: Checker) {
        c.section("docking geometry")
        let t = Docking.threshold(scale: 2)
        c.equal("threshold scales", t, 16)

        // A window 5 px below another snaps flush to its bottom edge.
        let anchor = CGRect(x: 100, y: 500, width: 275, height: 116)
        let floating = CGRect(x: 103, y: 500 - 116 - 5, width: 275, height: 116)
        let snapped = Docking.snap(frame: floating, to: [anchor], screen: nil, threshold: 8)
        c.equal("snaps x", snapped.x, 100)
        c.equal("snaps y flush under", snapped.y, anchor.minY - 116)

        // Too far away: nothing moves.
        let far = CGRect(x: 400, y: 100, width: 275, height: 116)
        let unmoved = Docking.snap(frame: far, to: [anchor], screen: nil, threshold: 8)
        c.equal("far window keeps its origin", unmoved, far.origin)

        // Screen edges.
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let nearEdge = CGRect(x: 4, y: 900 - 116 - 6, width: 275, height: 116)
        let clamped = Docking.snap(frame: nearEdge, to: [], screen: screen, threshold: 8)
        c.equal("snaps to the left edge", clamped.x, 0)
        c.equal("snaps to the top edge", clamped.y, 900 - 116)

        // Adjacency and transitive groups.
        let main = CGRect(x: 0, y: 232, width: 275, height: 116)
        let eq = CGRect(x: 0, y: 116, width: 275, height: 116)
        let pl = CGRect(x: 0, y: 0, width: 275, height: 116)
        c.check("main and eq are adjacent", Docking.isAdjacent(main, eq))
        c.check("main and playlist are not directly adjacent", !Docking.isAdjacent(main, pl))
        let group = Docking.dockedGroup(anchor: main, frames: [eq, pl])
        c.check("playlist travels with main through the eq", group == [0, 1])
        let detached = Docking.dockedGroup(anchor: main, frames: [CGRect(x: 600, y: 0, width: 275, height: 116)])
        c.check("a detached window does not travel", detached.isEmpty)

        // The default column: main, then Sessions, then Token Flow (SPEC 2.7).
        let column = Docking.defaultColumn(topLeft: CGPoint(x: 10, y: 900), scale: 2,
                                           heights: [116, 232, 232])
        c.equal("column: main at the top", column[0], CGPoint(x: 10, y: 900 - 232))
        c.equal("column: sessions under main", column[1], CGPoint(x: 10, y: 900 - 232 - 464))
        c.equal("column: token flow under sessions", column[2], CGPoint(x: 10, y: 900 - 232 - 464 - 464))
        c.check("an empty column is empty",
                Docking.defaultColumn(topLeft: .zero, scale: 2, heights: []).isEmpty)
    }

    // MARK: - Playlist geometry

    // MARK: - Scale (SPEC 2.8, amendment A2)

    private static func scaleModel(_ c: Checker) {
        c.section("scale model (ppsp)")

        c.equal("1x display offers 1x/2x/3x", ScaleModel.validPointScales(backing: 1), [1, 2, 3])
        c.equal("Retina offers half steps", ScaleModel.validPointScales(backing: 2), [1, 1.5, 2, 2.5, 3])
        c.equal("every Retina step is a whole pixel count",
                ScaleModel.validPointScales(backing: 2).map { ScaleModel.ppsp(points: $0, backing: 2) },
                [2, 3, 4, 5, 6])
        c.equal("1.5x on Retina is 3 device px", ScaleModel.ppsp(points: 1.5, backing: 2), 3)
        c.equal("2x on a 1x display is 2 device px", ScaleModel.ppsp(points: 2, backing: 1), 2)

        // A stored 1.5x cannot be honoured on a 1x display; the nearest valid scale is used.
        c.equal("1.5x snaps on a 1x screen", ScaleModel.nearest(1.5, backing: 1), 2)
        c.equal("1.25x snaps to 1.5x on Retina", ScaleModel.nearest(1.25, backing: 2), 1.5)
        c.equal("out-of-range clamps low", ScaleModel.nearest(0.2, backing: 2), 1)
        c.equal("out-of-range clamps high", ScaleModel.nearest(9, backing: 2), 3)

        c.equal("D cycles up on Retina", ScaleModel.next(after: 1.5, backing: 2), 2)
        c.equal("D wraps at the top", ScaleModel.next(after: 3, backing: 2), 1)
        c.equal("D cycles on a 1x display", ScaleModel.next(after: 2, backing: 1), 3)

        // SPEC 2.8's worked examples: 275*s <= 0.22*W and 464*s <= 0.62*H.
        c.equal("1920x1200 HiDPI defaults to 1.5x",
                ScaleModel.defaultPointScale(visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1200), backing: 2), 1.5)
        c.equal("1440x900 HiDPI defaults to 1x",
                ScaleModel.defaultPointScale(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), backing: 2), 1)
        c.equal("never below 1x on a tiny screen",
                ScaleModel.defaultPointScale(visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600), backing: 1), 1)
        c.check("a big 1x display gets more than 1x",
                ScaleModel.defaultPointScale(visibleFrame: CGRect(x: 0, y: 0, width: 3840, height: 2160), backing: 1) >= 2)

        c.equal("label whole", ScaleModel.label(2), "2x")
        c.equal("label half", ScaleModel.label(1.5), "1.5x")

        // ceil() sizing: 275 x 1.5 = 412.5 -> a 413 pt window with a transparent sliver.
        c.equal("content width is ceiled",
                ScaleModel.contentSize(skin: Layout.Main.size, points: 1.5).width, 413)
        c.equal("docking uses the exact size",
                ScaleModel.exactSize(skin: Layout.Main.size, points: 1.5).width, 412.5)

        // Docking maths must stay flush at a fractional scale.
        let column = Docking.defaultColumn(topLeft: CGPoint(x: 100, y: 1000), scale: 1.5,
                                           heights: [Layout.Main.size.h,
                                                     Layout.Playlist.defaultSize.h])
        c.close("sessions sit exactly under main at 1.5x", column[1].y,
                1000 - 1.5 * Double(Layout.Main.size.h) - 1.5 * Double(Layout.Playlist.defaultSize.h),
                1e-9)
        c.close("snap threshold scales", Double(Docking.threshold(scale: 1.5)), 12, 1e-9)

        // Device alignment of window origins.
        let aligned = SkinWindow.deviceAligned(CGPoint(x: 100.3, y: 50.7), backing: 2)
        c.close("origin snaps to the device grid (x)", Double(aligned.x), 100.5, 1e-9)
        c.close("origin snaps to the device grid (y)", Double(aligned.y), 50.5, 1e-9)
    }

    // MARK: - plfont (SPEC 3.2, amendment A1)

    private static func playlistFont(_ c: Checker, tmp: URL) {
        c.section("playlist bitmap font (plfont)")

        // Metrics parsing, including the CRLF trap and case-insensitive keys.
        let ini = "[PlaylistFont]\r\nMonospace=0\r\nSpacing=2\r\nSPACEWIDTH=4\r\nRowHeight=11\r\nOffsetY=1\r\n"
        let m = PlaylistFontMetrics.parse(Data(ini.utf8))
        c.equal("spacing", m.spacing, 2)
        c.equal("space width", m.spaceWidth, 4)
        c.equal("row height", m.rowHeight, 11)
        c.equal("offset y", m.offsetY, 1)
        c.check("monospace off", m.monospace == false)
        c.check("empty file -> all defaults", PlaylistFontMetrics.parse(Data()).spaceWidth == nil)

        // Text policy: fold to ASCII, keep the ellipsis, replace what is left.
        c.equal("diacritics fold", PlaylistFont.sanitize("Café"), "Cafe")
        c.equal("curly quotes fold", PlaylistFont.sanitize("\u{2018}x\u{2019} \u{201C}y\u{201D}"), "'x' \"y\"")
        c.equal("dashes fold", PlaylistFont.sanitize("a\u{2014}b"), "a-b")
        c.equal("ellipsis survives", PlaylistFont.sanitize("a\u{2026}"), "a\u{2026}")
        c.equal("unmappable becomes ?", PlaylistFont.sanitize("\u{4E2D}"), "?")
        c.check("lower case is kept (the sheet has real lowercase)",
                PlaylistFont.sanitize("Mixed Case") == "Mixed Case")

        // A synthetic 16x6 sheet with known ink: cell 'A' inked in columns 1...2, the ellipsis
        // cell fully inked, every other cell blank.
        let cellW = 4, cellH = 5
        let sheetW = cellW * PlaylistFont.columns, sheetH = cellH * PlaylistFont.rows
        func cellRect(_ k: Int) -> (x: Int, y: Int) {
            ((k % PlaylistFont.columns) * cellW, (k / PlaylistFont.columns) * cellH)
        }
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        guard let sheet = ImageMaker.make(width: sheetW, height: sheetH, { canvas in
            canvas.fill(CGRect(x: 0, y: 0, width: CGFloat(sheetW), height: CGFloat(sheetH)),
                        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            let a = cellRect(Int(Character("A").asciiValue!) - 32)
            canvas.fill(CGRect(x: CGFloat(a.x + 1), y: CGFloat(a.y), width: 2, height: CGFloat(cellH)), white)
            let e = cellRect(PlaylistFont.ellipsisCell)
            canvas.fill(CGRect(x: CGFloat(e.x), y: CGFloat(e.y), width: CGFloat(cellW), height: CGFloat(cellH)), white)
        }) else {
            c.check("synthetic plfont sheet", false)
            return
        }

        guard let font = PlaylistFont(sheet: sheet, metrics: nil) else {
            c.check("synthetic plfont loads", false)
            return
        }
        c.equal("cell width", font.cellW, cellW)
        c.equal("cell height", font.cellH, cellH)
        c.equal("default row height is cellH + 1", font.rowHeight, cellH + 1)
        c.equal("default space width", font.spaceWidth, max(2, cellW / 2 - 1))
        // advance = R - L + 1 + Spacing
        c.equal("proportional advance", font.advance("A"), 2 + 1)
        c.equal("blank cell advances SpaceWidth", font.advance(" "), font.spaceWidth)
        c.equal("ellipsis advance", font.advance("\u{2026}"), cellW + 1)
        c.equal("measure drops the trailing gap", font.measure("A"), 2)
        c.equal("measure of a run", font.measure("A A"), 3 + font.spaceWidth + 2)
        c.equal("empty string measures 0", font.measure(""), 0)

        // Monospace mode ignores the ink extents.
        var mono = PlaylistFontMetrics()
        mono.monospace = true
        if let monoFont = PlaylistFont(sheet: sheet, metrics: mono) {
            c.equal("monospace advance is the cell", monoFont.advance("A"), cellW)
            c.equal("monospace blank advances too", monoFont.advance(" "), cellW)
        } else {
            c.check("monospace font loads", false)
        }

        // Truncation never exceeds the budget and ends in the ellipsis glyph.
        let long = "AAAAAAAA"
        let cut = font.truncate(long, maxWidth: 12)
        c.check("truncated fits the budget", font.measure(cut) <= 12)
        c.check("truncated ends in an ellipsis", cut.hasSuffix("\u{2026}"))
        c.equal("short text is not truncated", font.truncate("A", maxWidth: 100), "A")
        c.equal("no room at all", font.truncate("A", maxWidth: 0), "")

        // A sheet that is not a clean 16x6 grid is ignored (SPEC 3.2).
        if let odd = ImageMaker.make(width: 13, height: 7, { $0.fill(CGRect(x: 0, y: 0, width: 13, height: 7), white) }) {
            c.check("a ragged grid is rejected", PlaylistFont(sheet: odd, metrics: nil) == nil)
        }

        // Tinted glyphs: the ink must come out as the tint, and blanks must draw nothing.
        let tint = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        if let canvas = SkinCanvas.offscreen(width: 8, height: cellH, scale: 1) {
            canvas.fill(CGRect(x: 0, y: 0, width: 8, height: CGFloat(cellH)),
                        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            font.draw("A", on: canvas, x: 1, y: 0, tint: tint)
            if let image = canvas.makeImage(), let px = pixels(of: image) {
                // 'A' has ink in cell columns 1...2, blitted so that column 1 lands on the pen (x=1).
                c.check("glyph ink is tinted", px(1, 2).0 > 200 && px(1, 2).1 < 60)
                c.check("glyph ink is 2 columns wide", px(2, 2).0 > 200)
                c.check("nothing bleeds past the glyph", px(4, 2).0 < 60)
                c.check("the row background survives left of the pen", px(0, 2).0 < 60)
            } else {
                c.check("tinted glyph renders", false)
            }
        }

        // The real Base skin ships a plfont: it must be found, and its RowHeight must win over
        // the layout default (SPEC 3.2 replaces layout.playlist.rowHeight).
        let base = Skin.base
        if base.hasOwnPlaylistFont, let f = base.playlistFont {
            c.equal("Base plfont cell", SkinPair(f.cellW, f.cellH), SkinPair(8, 10))
            c.equal("Base plfont row height", f.rowHeight, 11)
            c.check("Base row height reaches the skin", base.playlistRowHeight == f.rowHeight)
            c.check("Base draws real lowercase", f.advance("a") > 0 && f.advance("g") > 0)
            c.check("digits are inked", "0123456789$.".allSatisfy { f.advance($0) > 1 })
        } else {
            c.skip("Base plfont", "no bundled Base skin with a plfont on this checkout")
        }
        _ = tmp
    }

    /// (x, y) -> (r, g, b) of a rendered image, for pixel assertions.
    private static func pixels(of image: CGImage) -> ((Int, Int) -> (Int, Int, Int))? {
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            return true
        }
        guard ok else { return nil }
        return { x, y in
            guard x >= 0, y >= 0, x < w, y < h else { return (0, 0, 0) }
            let i = (y * w + x) * 4
            return (Int(buffer[i]), Int(buffer[i + 1]), Int(buffer[i + 2]))
        }
    }

    private static func playlistGeometry(_ c: Checker) {
        c.section("playlist geometry")
        c.equal("default height", Layout.Playlist.defaultSize.h, 232)
        c.equal("29 px steps", PlaylistRenderer.snapHeight(232 + 15), 232 + 29)
        c.equal("snaps down", PlaylistRenderer.snapHeight(232 + 10), 232)
        c.equal("never below the minimum", PlaylistRenderer.snapHeight(10), Layout.Playlist.minSize.h)
        c.check("every snapped height is on the grid",
                (0...20).allSatisfy { (PlaylistRenderer.snapHeight(100 + $0 * 17) - Layout.Playlist.minSize.h) % 29 == 0 })
        c.equal("rows at the default size", PlaylistRenderer.visibleRows(height: 232), 13)
        c.equal("rows at the minimum size", PlaylistRenderer.visibleRows(height: 116), 4)
        // The skin's plfont sets the row pitch (SPEC 3.2), so the row count follows it.
        c.equal("rows at an 11 px pitch", PlaylistRenderer.visibleRows(height: 232, rowHeight: 11), 15)
        c.equal("a nonsense pitch cannot divide by zero", PlaylistRenderer.visibleRows(height: 232, rowHeight: 0), 174)
        c.equal("row hit uses the same pitch",
                PlaylistRenderer.rowIndex(at: CGPoint(x: 100, y: 20 + 22 + 1), width: 275, height: 232,
                                          scroll: 0, count: 8, rowHeight: 11), 2)
        let area = PlaylistRenderer.listRect(width: 275, height: 232)
        c.equal("list area", area, SpriteRect(12, 20, 275 - 32, 232 - 58))
        c.equal("row 0 hit", PlaylistRenderer.rowIndex(at: CGPoint(x: 100, y: 25), width: 275, height: 232,
                                                      scroll: 0, count: 8), 0)
        c.equal("row 2 hit", PlaylistRenderer.rowIndex(at: CGPoint(x: 100, y: 20 + 26 + 1), width: 275, height: 232,
                                                      scroll: 0, count: 8), 2)
        c.equal("scrolled row hit", PlaylistRenderer.rowIndex(at: CGPoint(x: 100, y: 25), width: 275, height: 232,
                                                             scroll: 3, count: 8), 3)
        c.equal("past the last row", PlaylistRenderer.rowIndex(at: CGPoint(x: 100, y: 25), width: 275, height: 232,
                                                              scroll: 0, count: 0), nil)
        c.equal("outside the list", PlaylistRenderer.rowIndex(at: CGPoint(x: 100, y: 5), width: 275, height: 232,
                                                             scroll: 0, count: 8), nil)
    }

    // MARK: - Font map

    private static func fontMap(_ c: Checker) {
        c.section("bitmap font map")
        c.equal("A is row 0 col 0", BitmapFont.rect(for: "A"), SpriteRect(0, 0, 5, 6))
        c.equal("Z is row 0 col 25", BitmapFont.rect(for: "Z"), SpriteRect(125, 0, 5, 6))
        c.equal("0 is row 1 col 0", BitmapFont.rect(for: "0"), SpriteRect(0, 6, 5, 6))
        c.equal("9 is row 1 col 9", BitmapFont.rect(for: "9"), SpriteRect(45, 6, 5, 6))
        c.equal("colon", BitmapFont.rect(for: ":"), SpriteRect(60, 6, 5, 6))
        c.equal("dollar", BitmapFont.rect(for: "$"), SpriteRect(145, 6, 5, 6))
        c.equal("question mark is row 2", BitmapFont.rect(for: "?"), SpriteRect(15, 12, 5, 6))
        c.equal("space is cell [0,30]", BitmapFont.rect(for: " "), SpriteRect(150, 0, 5, 6))
        c.equal("lower case folds up", BitmapFont.rect(for: "a"), BitmapFont.rect(for: "A"))
        c.equal("unknown -> space", BitmapFont.rect(for: "\u{1F600}"), BitmapFont.rect(for: " "))
        c.equal("tilde -> space", BitmapFont.rect(for: "~"), BitmapFont.rect(for: " "))
        c.equal("sanitize upper-cases", BitmapFont.sanitize("hello"), "HELLO")
        c.equal("sanitize replaces", BitmapFont.sanitize("a~b"), "A B")
        c.check("every glyph fits inside text.bmp", BitmapFont.charset.allSatisfy {
            let r = BitmapFont.rect(for: $0)
            let sheet = SkinSpec.sheets[.text]!
            return r.x + r.w <= sheet.width && r.y + r.h <= sheet.height
        })
        c.check("charset covers the digits and A-Z",
                "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".allSatisfy { BitmapFont.charset.contains($0) })
    }

    // MARK: - Text file parsers

    private static func textFileParsers(_ c: Checker) {
        c.section("viscolor / pledit / region parsers")

        // CRLF, comments, stray spaces, a short file.
        let vis = "0,0,0 // background\r\n24,33,41   ; dots\r\n\r\n255,255,255 bars top\r\n// a comment line\r\n"
        let parsed = VisColors.parse(Data(vis.utf8))
        c.equal("24 colours always", parsed.rgb.count, 24)
        c.check("first colour", parsed.rgb[0] == (0, 0, 0))
        c.check("second colour", parsed.rgb[1] == (24, 33, 41))
        c.check("third colour", parsed.rgb[2] == (255, 255, 255))
        c.check("missing entries fall back", parsed.rgb[23] == VisColors.defaultRGB[23])
        c.check("empty file -> stock palette", VisColors.parse(Data()).rgb[5] == VisColors.defaultRGB[5])
        c.check("garbage -> stock palette", VisColors.parse(Data("not a colour file".utf8)).rgb[2] == VisColors.defaultRGB[2])
        // Latin-1 bytes must not kill the parse.
        var latin = Data("255,0,0 caf".utf8)
        latin.append(0xE9)
        latin.append(contentsOf: Array("\n0,255,0\n".utf8))
        c.check("latin-1 tolerated", VisColors.parse(latin).rgb[0] == (255, 0, 0))

        let pl = "\r\n; a comment\r\n[Text]\r\nNormal = 00FF00\r\nCURRENT=#FFFFFF\r\nNormalBG=#000080\r\nSelectedBG=0000FF\r\nFont=Tahoma\r\n"
        let colours = PleditColors.parse(Data(pl.utf8))
        c.equal("font name", colours.fontName, "Tahoma")
        c.check("case-insensitive keys", colours.current == CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        c.check("hash optional", colours.normal == CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        c.check("missing file -> defaults", PleditColors.parse(Data()).fontName == PleditColors.fallback.fontName)
        c.check("3-digit hex", PleditColors.parseHexColor("#0f0") == CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        c.check("bad hex -> nil", PleditColors.parseHexColor("zzz") == nil)

        let region = """
        [Normal]
        NumPoints=4,3
        PointList=0,0, 275,0, 275,116, 0,116, 10,10, 20,10, 15,20
        [Equalizer]
        NumPoints=4
        PointList=0,0,275,0,275,116,0,116
        """
        let regions = SkinRegions.parse(Data(region.utf8))
        c.equal("two polygons", regions[.normal]?.polygons.count, 2)
        c.equal("first polygon has 4 points", regions[.normal]?.polygons.first?.count, 4)
        c.equal("second polygon has 3 points", regions[.normal]?.polygons.last?.count, 3)
        c.equal("equalizer section", regions[.equalizer]?.polygons.first?.count, 4)
        c.check("missing section", regions[.windowShade] == nil)
        c.check("garbage region file", SkinRegions.parse(Data("nonsense".utf8))[.normal] == nil)
        c.check("region path is non-empty", regions[.normal]?.path().isEmpty == false)
    }

    // MARK: - ZIP

    private static func zipReader(_ c: Checker, tmp: URL) {
        c.section("zip reader")

        // 1. Stored entries built in memory.
        let stored = TestZip.make([("main.bmp", Data(repeating: 0xAB, count: 300)),
                                   ("viscolor.txt", Data("0,0,0\n".utf8))], dataDescriptor: false)
        if let archive = try? ZipArchive(data: stored) {
            c.equal("stored: two entries", archive.entries.count, 2)
            c.equal("stored: payload round-trips", try? archive.data(for: "main.bmp"),
                    Data(repeating: 0xAB, count: 300))
            c.equal("stored: text round-trips", (try? archive.data(for: "viscolor.txt")).map { decodeSkinText($0) },
                    "0,0,0\n")
        } else {
            c.check("stored zip parses", false)
        }

        // 2. Data descriptor: local header sizes are zero, the central directory is authoritative.
        let descriptor = TestZip.make([("a.txt", Data("hello".utf8))], dataDescriptor: true)
        if let archive = try? ZipArchive(data: descriptor) {
            c.equal("data descriptor: payload", (try? archive.data(for: "a.txt")).map { decodeSkinText($0) }, "hello")
        } else {
            c.check("data-descriptor zip parses", false)
        }

        // 3. Not a zip / truncated.
        c.check("garbage is rejected", (try? ZipArchive(data: Data(repeating: 0x7F, count: 512))) == nil)
        c.check("empty data is rejected", (try? ZipArchive(data: Data())) == nil)
        var truncated = stored
        truncated.removeLast(10)
        c.check("truncated archive is rejected, not crashed", (try? ZipArchive(data: truncated)) == nil)

        // 3b. A hostile central directory that declares a huge uncompressed size must be refused
        // before we allocate a buffer for it, not obeyed.
        let bomb = TestZip.make([("main.bmp", Data(repeating: 0, count: 64))], dataDescriptor: false,
                                declaredUncompressedSize: 3 << 30)
        if let archive = try? ZipArchive(data: bomb), let entry = archive.entries.first {
            c.equal("a bomb's declared size survives parsing", entry.uncompressedSize, 3 << 30)
            var refused = false
            do { _ = try archive.extract(entry) } catch { refused = true }
            c.check("an absurd declared size is refused, not allocated", refused)
        } else {
            c.check("bomb archive parses", false)
        }
        c.check("the member cap is sane", ZipArchive.maximumMemberBytes >= 16 << 20)

        // 4. Encrypted entries are skipped rather than exploding.
        let encrypted = TestZip.make([("secret.bmp", Data("x".utf8))], dataDescriptor: false, encryptedFlag: true)
        if let archive = try? ZipArchive(data: encrypted) {
            c.equal("encrypted entry is skipped", archive.entries.count, 0)
            c.equal("encrypted entry is reported", archive.skipped.count, 1)
        } else {
            c.check("encrypted zip still parses", false)
        }

        // 5. Real deflate, via /usr/bin/zip.
        let zipBin = "/usr/bin/zip"
        if FileManager.default.isExecutableFile(atPath: zipBin) {
            let dir = tmp.appendingPathComponent("ziptest", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Highly compressible content, so deflate is definitely chosen.
            let body = String(repeating: "TOKENAMP DEFLATE TEST 0123456789\n", count: 400)
            try? body.write(to: dir.appendingPathComponent("payload.txt"), atomically: true, encoding: .utf8)
            let out = tmp.appendingPathComponent("deflate.zip")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: zipBin)
            p.arguments = ["-q", "-9", "-j", out.path, dir.appendingPathComponent("payload.txt").path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
            if let archive = try? ZipArchive(url: out), let entry = archive.entries.first {
                c.equal("deflate: method 8", entry.method, 8)
                c.check("deflate: actually compressed", entry.compressedSize < entry.uncompressedSize)
                c.equal("deflate: inflates exactly", (try? archive.extract(entry)).map { decodeSkinText($0) }, body)
            } else {
                c.check("/usr/bin/zip archive parses", false)
            }
        } else {
            c.skip("deflate round-trip", "/usr/bin/zip not present")
        }
    }

    // MARK: - Skin loading robustness (SPEC 3, acceptance check 4)

    private static func skinLoading(_ c: Checker, tmp: URL) {
        c.section("skin loading robustness")
        let fm = FileManager.default

        // A folder skin with MiXeD case names, a missing optional sheet, an undersized sheet and
        // a garbage file that is not an image at all.
        let dir = tmp.appendingPathComponent("MixedSkin", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        writeBMP(dir.appendingPathComponent("MAIN.BMP"), width: 275, height: 116, colour: (30, 40, 60))
        writeBMP(dir.appendingPathComponent("TitleBar.Bmp"), width: 344, height: 87, colour: (60, 40, 30))
        writeBMP(dir.appendingPathComponent("cbuttons.bmp"), width: 20, height: 8, colour: (10, 200, 10))  // undersized
        try? Data("this is not a bitmap at all".utf8).write(to: dir.appendingPathComponent("pledit.bmp"))
        try? "0,0,0\r\n1,2,3 ; comment\r\n".write(to: dir.appendingPathComponent("VISCOLOR.TXT"),
                                                 atomically: true, encoding: .utf8)
        try? Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: dir.appendingPathComponent("junk.dat"))

        if let skin = try? SkinLoader.load(url: dir) {
            c.check("mixed-case names are found", skin.hasOwnSheet(.main))
            c.check("mixed-case extension is found", skin.hasOwnSheet(.titlebar))
            c.check("missing optional sheet is tolerated", !skin.hasOwnSheet(.eqmain))
            c.check("undersized sheet still loads", skin.hasOwnSheet(.cbuttons))
            c.check("a sprite outside an undersized sheet does not crash",
                    skin.image(Spr.MAIN_EJECT_BUTTON) != nil || skin.image(Spr.MAIN_EJECT_BUTTON) == nil)
            c.check("undecodable sheet becomes a warning", skin.warnings.contains { $0.contains("pledit") })
            c.check("viscolor was read", skin.visColors.rgb[1] == (1, 2, 3))
            c.check("missing sheets fall back to Base", skin.sheet(.eqmain) != nil)
            c.check("every named sprite is reachable or nil, never a crash",
                    SheetID.allCases.allSatisfy { sheet in
                        (SkinSpec.spriteRects[sheet] ?? [:]).allSatisfy { name, rect in
                            _ = skin.crop(sheet, rect)
                            _ = name
                            return true
                        }
                    })
            c.check("digit lookup never crashes",
                    "0123456789- ".allSatisfy { _ = skin.digitSprite($0); return true })
            c.check("every font glyph is reachable",
                    BitmapFont.charset.allSatisfy { _ = skin.font.glyph($0); return true })
        } else {
            c.check("folder skin loads", false)
        }

        // The same files, zipped inside a nested directory, with a junk member.
        let nested = tmp.appendingPathComponent("nested.wsz")
        let entries: [(String, Data)] = [
            ("My Skin/MAIN.BMP", (try? Data(contentsOf: dir.appendingPathComponent("MAIN.BMP"))) ?? Data()),
            ("My Skin/nested/TEXT.BMP", makeBMPData(width: 155, height: 74, colour: (5, 5, 5))),
            ("My Skin/viscolor.txt", Data("9,9,9\n".utf8)),
            ("__MACOSX/._MAIN.BMP", Data([0, 1, 2, 3])),
            ("My Skin/readme.txt", Data("hello".utf8)),
        ]
        try? TestZip.make(entries, dataDescriptor: false).write(to: nested)
        if let skin = try? SkinLoader.load(url: nested) {
            c.check("zip: directory prefixes are ignored", skin.hasOwnSheet(.main))
            c.check("zip: nested subdirectories are found", skin.hasOwnSheet(.text))
            c.check("zip: viscolor inside the archive", skin.visColors.rgb[0] == (9, 9, 9))
            c.check("zip: __MACOSX members are ignored", !skin.warnings.contains { $0.contains("__MACOSX") })
        } else {
            c.check("nested zip skin loads", false)
        }

        // A .png beats a .bmp of the same name.
        let pngDir = tmp.appendingPathComponent("PngSkin", isDirectory: true)
        try? fm.createDirectory(at: pngDir, withIntermediateDirectories: true)
        writeBMP(pngDir.appendingPathComponent("main.bmp"), width: 275, height: 116, colour: (255, 0, 0))
        if let png = ImageMaker.make(width: 275, height: 116, { $0.fill(CGRect(x: 0, y: 0, width: 275, height: 116),
                                                                        CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)) }),
           let data = ImageMaker.pngData(png) {
            try? data.write(to: pngDir.appendingPathComponent("MAIN.PNG"))
            if let skin = try? SkinLoader.load(url: pngDir), let sheet = skin.rawSheet(.main) {
                c.check("png wins over bmp", isBlue(sheet))
            } else {
                c.check("png skin loads", false)
            }
        } else {
            c.skip("png beats bmp", "could not encode a test png")
        }

        // Nothing usable at all.
        let emptyDir = tmp.appendingPathComponent("EmptySkin", isDirectory: true)
        try? fm.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        c.check("an empty folder is an error, not a crash", (try? SkinLoader.load(url: emptyDir)) == nil)
        let garbage = tmp.appendingPathComponent("garbage.wsz")
        try? Data(repeating: 0x55, count: 2048).write(to: garbage)
        c.check("a garbage .wsz is an error, not a crash", (try? SkinLoader.load(url: garbage)) == nil)
        c.check("a missing path is an error", (try? SkinLoader.load(url: tmp.appendingPathComponent("nope.wsz"))) == nil)

        // REGRESSION (critical): pledit.bmp and pledit.txt share a stem, and so do plfont.bmp and
        // plfont.txt. Keyed by stem alone, whichever of the pair the enumerator reached second was
        // silently dropped - which is how every skin's playlist colours ended up as the built-in
        // green-on-black defaults. Both orders must work, in a folder and in an archive.
        for (label, plainTextFirst) in [("bitmap first", false), ("text first", true)] {
            let pair = tmp.appendingPathComponent("Pair-\(plainTextFirst)", isDirectory: true)
            try? fm.createDirectory(at: pair, withIntermediateDirectories: true)
            writeBMP(pair.appendingPathComponent("main.bmp"), width: 275, height: 116, colour: (1, 2, 3))
            writeBMP(pair.appendingPathComponent("pledit.bmp"), width: 280, height: 186, colour: (9, 9, 9))
            try? "[Text]\r\nNormal=#7CF0A6\r\nCurrent=#B7F7CE\r\nNormalBG=#0A1512\r\nSelectedBG=#224E34\r\n"
                .write(to: pair.appendingPathComponent("pledit.txt"), atomically: true, encoding: .utf8)
            if let skin = try? SkinLoader.load(url: pair) {
                c.check("\(label): the pledit sheet still decodes", skin.hasOwnSheet(.pledit))
                c.check("\(label): pledit.txt is parsed, not shadowed by pledit.bmp",
                        skin.pledit.normal == CGColor(srgbRed: 124.0 / 255, green: 240.0 / 255, blue: 166.0 / 255, alpha: 1))
                c.check("\(label): the list background comes from the skin",
                        skin.pledit.normalBG == CGColor(srgbRed: 10.0 / 255, green: 21.0 / 255, blue: 18.0 / 255, alpha: 1))
            } else {
                c.check("\(label): paired skin loads", false)
            }
        }

        // The same pairing inside an archive, with the text member written *before* the bitmap.
        let paired = tmp.appendingPathComponent("paired.wsz")
        let pairedEntries: [(String, Data)] = [
            ("pledit.txt", Data("[Text]\nNormal=#112233\n".utf8)),
            ("pledit.bmp", makeBMPData(width: 280, height: 186, colour: (4, 5, 6))),
            ("plfont.txt", Data("[PlaylistFont]\nRowHeight=9\nSpacing=1\n".utf8)),
            ("plfont.bmp", makeBMPData(width: 32, height: 12, colour: (255, 255, 255))),
            ("main.bmp", makeBMPData(width: 275, height: 116, colour: (7, 7, 7))),
        ]
        try? TestZip.make(pairedEntries, dataDescriptor: false).write(to: paired)
        if let skin = try? SkinLoader.load(url: paired) {
            c.check("zip: text member does not shadow the bitmap", skin.hasOwnSheet(.pledit))
            c.check("zip: pledit colours are read",
                    skin.pledit.normal == CGColor(srgbRed: 17.0 / 255, green: 34.0 / 255, blue: 51.0 / 255, alpha: 1))
            c.check("zip: plfont sheet is picked up", skin.hasOwnPlaylistFont)
            c.equal("zip: plfont.txt RowHeight wins", skin.playlistFont?.rowHeight, 9)
            c.equal("zip: plfont cell size", skin.playlistFont.map { SkinPair($0.cellW, $0.cellH) }, SkinPair(2, 2))
        } else {
            c.check("paired archive loads", false)
        }

        // A skin with no plfont of its own borrows Base's, tinted with its own pledit colours.
        if let skin = try? SkinLoader.load(url: dir) {
            c.check("a skin without plfont still gets a bitmap typeface",
                    skin.playlistFont != nil || Skin.base.playlistFont == nil)
            c.check("it is not the skin's own", !skin.hasOwnPlaylistFont)
        }

        // Base always resolves to something drawable.
        c.check("Base skin has a main sheet", Skin.base.sheet(.main) != nil)
        c.check("Base skin has a font", Skin.base.font.glyph("A") != nil)
        c.check("Base skin has digits", Skin.base.digitSprite("7") != nil)
    }

    // MARK: - Rendering smoke test

    private static func rendering(_ c: Checker) {
        c.section("rendering")
        let snap = DemoUsageProvider(frozenAt: DemoUsageProvider.referenceDate).snapshot
        let skin = Skin.base
        let state = SnapshotRunner.makeState(snapshot: snap, scale: 1, now: DemoUsageProvider.referenceDate)

        for (name, w, h, body) in [
            ("main", Layout.Main.size.w, Layout.Main.size.h, { (c: SkinCanvas) in
                MainRenderer.draw(c, skin: skin, snapshot: snap, state: state) }),
            ("shade", Layout.Shade.size.w, Layout.Shade.size.h, { (c: SkinCanvas) in
                MainRenderer.drawShade(c, skin: skin, snapshot: snap, state: state) }),
            ("eq", Layout.EQ.size.w, Layout.EQ.size.h, { (c: SkinCanvas) in
                EQRenderer.draw(c, skin: skin, snapshot: snap, state: state) }),
            ("playlist", state.playlistWidth, state.playlistHeight, { (c: SkinCanvas) in
                PlaylistRenderer.draw(c, skin: skin, snapshot: snap, state: state) }),
        ] {
            guard let canvas = SkinCanvas.offscreen(width: w, height: h, scale: 1) else {
                c.check("\(name): canvas", false)
                continue
            }
            body(canvas)
            guard let image = canvas.makeImage() else {
                c.check("\(name): image", false)
                continue
            }
            c.equal("\(name): pixel size", SkinPair(image.width, image.height), SkinPair(w, h))
            c.check("\(name): not blank", !isUniform(image))
        }

        // An empty snapshot must render without trapping.
        let empty = UsageSnapshot.empty(at: DemoUsageProvider.referenceDate)
        var emptyState = SnapshotRunner.makeState(snapshot: empty, scale: 1, now: DemoUsageProvider.referenceDate)
        emptyState.visualizerMode = .oscilloscope
        if let canvas = SkinCanvas.offscreen(width: Layout.Main.size.w, height: Layout.Main.size.h, scale: 1) {
            MainRenderer.draw(canvas, skin: skin, snapshot: empty, state: emptyState)
            c.check("empty snapshot renders", canvas.makeImage() != nil)
        } else {
            c.check("empty snapshot canvas", false)
        }
        // ...at every scale, and in every visualizer mode.
        for scale in 1...3 {
            for mode in VisualizerMode.allCases {
                var s = state
                s.scale = Double(scale)
                s.visualizerMode = mode
                guard let canvas = SkinCanvas.offscreen(width: Layout.Main.size.w, height: Layout.Main.size.h,
                                                        scale: scale) else {
                    c.check("scale \(scale) canvas", false)
                    continue
                }
                MainRenderer.draw(canvas, skin: skin, snapshot: snap, state: s)
                guard let img = canvas.makeImage() else {
                    c.check("scale \(scale)/\(mode.rawValue) image", false)
                    continue
                }
                c.equal("scale \(scale)/\(mode.rawValue) size", img.width, Layout.Main.size.w * scale)
            }
        }
    }

    // MARK: - Token Flow (SPEC 2.9)

    private static func tokenFlow(_ c: Checker) {
        c.section("token flow")
        let now = DemoUsageProvider.referenceDate
        let snap = DemoUsageProvider(frozenAt: now).snapshot
        let skin = Skin.base

        // Geometry of the window itself.
        let well = FieldRenderer.canvasRect(width: Layout.Field.defaultSize.w,
                                            height: Layout.Field.defaultSize.h)
        c.equal("well width = window minus both rails",
                well.w, Layout.Field.defaultSize.w - Layout.Field.leftWidth - Layout.Field.rightWidth)
        c.equal("well height = window minus title and readout",
                well.h, Layout.Field.defaultSize.h - Layout.Field.titleHeight - Layout.Field.bottomHeight)
        c.equal("resize snaps to the width step",
                FieldRenderer.snapWidth(Layout.Field.minSize.w + 13),
                Layout.Field.minSize.w + Layout.Field.resizeStep.w)
        c.equal("resize never goes below the minimum",
                FieldRenderer.snapHeight(10), Layout.Field.minSize.h)
        c.check("every control has a region",
                Set(FieldRenderer.regions(width: 275, height: 232).map { $0.id })
                    .isSuperset(of: [.fieldClose, .fieldLamp, .fieldCanvas, .fieldResize, .fieldTitleBar]))

        // Modulators are pure functions of the snapshot.
        let mods = FieldModulators(snapshot: snap, now: now)
        c.check("pressure in range", mods.pressure >= 0 && mods.pressure <= 1)
        c.check("energy in range", mods.energy > 0 && mods.energy <= 1)
        c.check("persistence is a sane time constant", mods.persistence >= 0.35 && mods.persistence <= 2.3)
        c.check("phase in range", mods.phase >= 0 && mods.phase <= 1)
        c.check("at least one beam", mods.beams >= 1)
        c.equal("modulators are deterministic", mods, FieldModulators(snapshot: snap, now: now))

        let idle = UsageSnapshot(generatedAt: now, lastEventAt: now.addingTimeInterval(-3_600))
        c.check("an idle account dims the field",
                FieldModulators(snapshot: idle, now: now).energy < mods.energy)

        // The director holds a choice for its dwell time, but a critical limit cuts in at once.
        var director = FieldDirector(start: .scope, now: now)
        let busy = UsageSnapshot(generatedAt: now, limits: [], activeSessionCount: 3, lastEventAt: now)
        let busyMods = FieldModulators(snapshot: busy, now: now)
        c.equal("two live sessions ask for the connectome",
                FieldDirector.preferred(busy, mods: busyMods, now: now), FieldMode.web)
        c.equal("but not the moment it is asked for",
                director.resolve(busy, mods: busyMods, now: now.addingTimeInterval(5)), FieldMode.scope)
        c.equal("and only once it has kept asking for a whole dwell",
                director.resolve(busy, mods: busyMods,
                                 now: now.addingTimeInterval(5 + FieldDirector.dwell + 1)), FieldMode.web)

        // A momentary blip must not flip a steady display: the debounce restarts when the answer
        // goes back to what is already on screen.
        var steady = FieldDirector(start: .scope, now: now)
        let calm = UsageSnapshot(generatedAt: now, activeSessionCount: 1, lastEventAt: now)
        let calmMods = FieldModulators(snapshot: calm, now: now)
        _ = steady.resolve(calm, mods: calmMods, now: now.addingTimeInterval(600))
        _ = steady.resolve(busy, mods: busyMods, now: now.addingTimeInterval(601))
        _ = steady.resolve(calm, mods: calmMods, now: now.addingTimeInterval(602))
        c.equal("one blip after a quiet hour does not switch anything",
                steady.resolve(busy, mods: busyMods, now: now.addingTimeInterval(603)), FieldMode.scope)

        // Idleness has two readings: nothing to look at, or a day's history worth reading.
        let quiet = UsageSnapshot(generatedAt: now, lastEventAt: now.addingTimeInterval(-1_800))
        c.equal("an idle account with no history shows the ring",
                FieldDirector.preferred(quiet, mods: FieldModulators(snapshot: quiet, now: now), now: now),
                FieldMode.orbit)
        var withHistory = quiet
        withHistory.sessionsToday = snap.sessionsToday
        c.equal("an idle account with a day behind it shows the ledger",
                FieldDirector.preferred(withHistory,
                                        mods: FieldModulators(snapshot: withHistory, now: now), now: now),
                FieldMode.strata)

        let nearReset = UsageSnapshot(
            generatedAt: now,
            limits: [LimitGauge(id: "session", kind: .session, title: "SESSION (5H)", percent: 40,
                                resetsAt: now.addingTimeInterval(300), windowSeconds: 18_000,
                                severity: "normal", isActive: true)],
            activeSessionCount: 3, lastEventAt: now)
        c.equal("a reset minutes away shows the ring, whatever else is happening",
                FieldDirector.preferred(nearReset,
                                        mods: FieldModulators(snapshot: nearReset, now: now), now: now),
                FieldMode.orbit)

        let critical = UsageSnapshot(
            generatedAt: now,
            limits: [LimitGauge(id: "session", kind: .session, title: "SESSION (5H)", percent: 97,
                                resetsAt: now.addingTimeInterval(1_200), windowSeconds: 18_000,
                                severity: "critical", isActive: true)],
            activeSessionCount: 3, lastEventAt: now)
        var hot = FieldDirector(start: .web, now: now)
        c.equal("a critical limit overrides the dwell",
                hot.resolve(critical, mods: FieldModulators(snapshot: critical, now: now),
                            now: now.addingTimeInterval(1)), FieldMode.orbit)

        // Every configuration renders, at every size, without trapping - including on no data.
        let empty = UsageSnapshot.empty(at: now)
        for mode in FieldMode.allCases {
            for (w, h) in [(Layout.Field.minSize.w, Layout.Field.minSize.h),
                           (Layout.Field.defaultSize.w, Layout.Field.defaultSize.h)] {
                let settled = FieldRenderer.settled(snapshot: snap, skin: skin, mode: mode,
                                                    span: .minutes, width: w, height: h, now: now)
                guard let image = settled.image else {
                    c.check("\(mode.rawValue) \(w)x\(h): image", false)
                    continue
                }
                let wellRect = FieldRenderer.canvasRect(width: w, height: h)
                c.equal("\(mode.rawValue) \(w)x\(h): fills the well",
                        SkinPair(image.width, image.height), SkinPair(wellRect.w, wellRect.h))
                c.check("\(mode.rawValue) \(w)x\(h): draws something", !isUniform(image))
            }
            c.check("\(mode.rawValue): empty snapshot renders",
                    FieldRenderer.settled(snapshot: empty, skin: skin, mode: mode, span: .minutes,
                                          width: 275, height: 232, now: now).image != nil)
        }

        // The settled field is what --snapshot writes, so it has to be reproducible.
        let a = FieldRenderer.settled(snapshot: snap, skin: skin, mode: .scope, span: .minutes,
                                      width: 275, height: 232, now: now)
        let b = FieldRenderer.settled(snapshot: snap, skin: skin, mode: .scope, span: .minutes,
                                      width: 275, height: 232, now: now)
        c.check("settled fields are identical", samePixels(a.image, b.image))

        // The live path steps the same buffer the settled render does, so stepping it by hand
        // has to stay bounded and land in the same place. (The window itself needs AppKit, but
        // this is the part that could drift or blow up.)
        let live = PhosphorField(width: well.w, height: well.h)
        for i in 0..<120 {
            live.decay(dt: 1.0 / 30, persistence: mods.persistence)
            _ = FieldGeometry.draw(.scope, into: live, snapshot: snap, mods: mods, span: .minutes,
                                   flows: [:], t: Double(i) / 30, now: now)
        }
        c.check("the live field stays finite", live.beam.allSatisfy { $0.isFinite && $0 >= 0 })
        c.check("the live field stays bounded", live.beam.allSatisfy { $0 < 50 })
        c.check("the live field draws something", live.beam.contains { $0 > 0.02 })
        live.decay(dt: 30, persistence: 0.4)
        c.check("a long gap fades it to nothing", live.beam.allSatisfy { $0 < 0.001 })

        // The whole window, chrome and all.
        var state = SnapshotRunner.makeState(snapshot: snap, scale: 1, now: now)
        state.fieldMode = .web
        let webField = FieldRenderer.settled(snapshot: snap, skin: skin, mode: .web, span: .minutes,
                                             width: state.fieldWidth, height: state.fieldHeight, now: now)
        c.check("the connectome labels its nodes", !webField.labels.isEmpty)
        c.check("labels stay in the classic charset",
                webField.labels.allSatisfy { $0.text.allSatisfy { BitmapFont.charset.contains($0) } })
        if let canvas = SkinCanvas.offscreen(width: state.fieldWidth, height: state.fieldHeight, scale: 1) {
            FieldRenderer.draw(canvas, skin: skin, snapshot: snap, state: state,
                               field: webField.image, labels: webField.labels)
            guard let image = canvas.makeImage() else {
                c.check("window renders", false)
                return
            }
            c.equal("window pixel size", SkinPair(image.width, image.height),
                    SkinPair(state.fieldWidth, state.fieldHeight))
            c.check("window is not blank", !isUniform(image))
        } else {
            c.check("window canvas", false)
        }

        // Per-session flow comes from diffing snapshots, because UsageModel has no time series.
        let tracker = SessionFlowTracker()
        guard let row = snap.sessionsToday.first else {
            c.check("demo data has a session to track", false)
            return
        }
        tracker.ingest(snap, now: now)
        c.equal("a first sighting is not flow", tracker.flow(row.id, now: now), 0)
        var moved = snap
        moved.sessionsToday[0].tokens.output += 300_000
        tracker.ingest(moved, now: now.addingTimeInterval(5))
        c.check("tokens arriving read as flow", tracker.flow(row.id, now: now.addingTimeInterval(5)) > 0)
        c.equal("and it fades out", tracker.flow(row.id, now: now.addingTimeInterval(600)), 0)
    }

    // MARK: - Small helpers

    private static func samePixels(_ a: CGImage?, _ b: CGImage?) -> Bool {
        guard let a, let b, a.width == b.width, a.height == b.height,
              let da = a.dataProvider?.data as Data?, let db = b.dataProvider?.data as Data? else { return false }
        return da == db
    }


    private static func isUniform(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data as Data? , data.count > 16 else { return true }
        let first = data.prefix(4)
        var i = 0
        while i + 4 <= data.count {
            if data.subdata(in: i..<(i + 4)) != first { return false }
            i += 4 * 97   // sample, do not scan every pixel
        }
        return true
    }

    private static func isBlue(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data as Data?, data.count >= 4 else { return false }
        // Whatever the channel order, a pure blue image has one channel at 255 and two near 0.
        let bytes = Array(data.prefix(4))
        let high = bytes.filter { $0 > 200 }.count
        let low = bytes.filter { $0 < 40 }.count
        return high >= 1 && low >= 2
    }

    private static func writeBMP(_ url: URL, width: Int, height: Int, colour: (UInt8, UInt8, UInt8)) {
        try? makeBMPData(width: width, height: height, colour: colour).write(to: url)
    }

    /// A minimal 24-bit BMP, written by hand so the tests do not depend on any encoder.
    static func makeBMPData(width: Int, height: Int, colour: (UInt8, UInt8, UInt8)) -> Data {
        let rowBytes = ((width * 3) + 3) & ~3
        let pixels = rowBytes * height
        var d = Data()
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func i32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: [0x42, 0x4D])                 // "BM"
        u32(UInt32(14 + 40 + pixels))
        u16(0); u16(0)
        u32(14 + 40)
        u32(40)                                            // BITMAPINFOHEADER
        i32(Int32(width)); i32(Int32(height))
        u16(1); u16(24)
        u32(0); u32(UInt32(pixels))
        i32(2835); i32(2835)
        u32(0); u32(0)
        var row = Data()
        for _ in 0..<width { row.append(contentsOf: [colour.2, colour.1, colour.0]) }  // BGR
        while row.count < rowBytes { row.append(0) }
        for _ in 0..<height { d.append(row) }
        return d
    }
}

/// A tiny ZIP writer used only by `--selftest`, so the reader is exercised against bytes this
/// process produced rather than a checked-in fixture.
enum TestZip {

    /// `declaredUncompressedSize` forges the central directory's size field (and marks the member
    /// deflated) so the reader's allocation bound can be exercised.
    static func make(_ entries: [(String, Data)], dataDescriptor: Bool, encryptedFlag: Bool = false,
                     declaredUncompressedSize: Int? = nil) -> Data {
        let method: UInt16 = declaredUncompressedSize == nil ? 0 : 8
        var out = Data()
        var central = Data()
        var offsets: [Int] = []

        for (name, payload) in entries {
            offsets.append(out.count)
            let nameBytes = Data(name.utf8)
            var flags: UInt16 = 0x0800                      // UTF-8 names
            if dataDescriptor { flags |= 0x0008 }
            if encryptedFlag { flags |= 0x0001 }
            append(&out, u32: 0x0403_4B50)
            append(&out, u16: 20)
            append(&out, u16: flags)
            append(&out, u16: method)
            append(&out, u16: 0); append(&out, u16: 0)      // time, date
            append(&out, u32: crc32(payload))
            append(&out, u32: dataDescriptor ? 0 : UInt32(payload.count))
            append(&out, u32: dataDescriptor ? 0 : UInt32(payload.count))
            append(&out, u16: UInt16(nameBytes.count))
            append(&out, u16: 0)
            out.append(nameBytes)
            out.append(payload)
            if dataDescriptor {
                append(&out, u32: 0x0807_4B50)
                append(&out, u32: crc32(payload))
                append(&out, u32: UInt32(payload.count))
                append(&out, u32: UInt32(payload.count))
            }
        }

        for (i, (name, payload)) in entries.enumerated() {
            let nameBytes = Data(name.utf8)
            var flags: UInt16 = 0x0800
            if dataDescriptor { flags |= 0x0008 }
            if encryptedFlag { flags |= 0x0001 }
            append(&central, u32: 0x0201_4B50)
            append(&central, u16: 20); append(&central, u16: 20)
            append(&central, u16: flags)
            append(&central, u16: method)
            append(&central, u16: 0); append(&central, u16: 0)
            append(&central, u32: crc32(payload))
            append(&central, u32: UInt32(payload.count))
            append(&central, u32: UInt32(declaredUncompressedSize ?? payload.count))
            append(&central, u16: UInt16(nameBytes.count))
            append(&central, u16: 0); append(&central, u16: 0)
            append(&central, u16: 0); append(&central, u16: 0)
            append(&central, u32: 0)
            append(&central, u32: UInt32(offsets[i]))
            central.append(nameBytes)
        }

        let cdOffset = out.count
        out.append(central)
        append(&out, u32: 0x0605_4B50)
        append(&out, u16: 0); append(&out, u16: 0)
        append(&out, u16: UInt16(entries.count))
        append(&out, u16: UInt16(entries.count))
        append(&out, u32: UInt32(central.count))
        append(&out, u32: UInt32(cdOffset))
        append(&out, u16: 0)
        return out
    }

    private static func append(_ d: inout Data, u16 v: UInt16) {
        withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
    }

    private static func append(_ d: inout Data, u32 v: UInt32) {
        withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
    }

    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}
