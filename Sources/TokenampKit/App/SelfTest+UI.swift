import CoreGraphics
import Foundation
import ImageIO
import UsageModel

/// Regression checks for a batch of UI defects: the hero track lost on every live launch, limit
/// alerts that repeated, the scale a trip to another display left behind, skin images whose
/// headers claim gigabytes, the Sessions list's scroll and selection, the one-device-pixel
/// docking seam at a fractional scale, and Sessions auto-fit with the windows docked below it
/// following its height (A7). Pure logic and files in the scratch folder only; no window is
/// created.
extension SelfTest {

    static func uiFixes(_ c: Checker, tmp: URL) {
        heroSurvivesEmptyTracklist(c)
        limitAlerts(c, tmp: tmp)
        scalePerScreen(c)
        hostileSkinImages(c, tmp: tmp)
        skinInstall(c, tmp: tmp)
        sessionsListState(c)
        dockingOnTheArt(c)
        sessionsAutoFit(c)
        dockedBelowFollowsHeight(c)
    }

    private static func gauge(_ id: String, _ kind: LimitGauge.Kind, _ percent: Double,
                              resets: Date?, window: TimeInterval = 18_000) -> LimitGauge {
        LimitGauge(id: id, kind: kind, title: id.uppercased(), percent: percent, resetsAt: resets,
                   windowSeconds: window)
    }

    // MARK: - 1. The hero track

    private static func heroSurvivesEmptyTracklist(_ c: Checker) {
        c.section("hero track: a snapshot without limits does not lose the pick")
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let three = [gauge("session", .session, 40, resets: now + 3_600),
                     gauge("weekly_all", .weeklyAll, 20, resets: now + 86_400, window: 604_800),
                     gauge("weekly_scoped:Fable", .weeklyScoped, 60, resets: now + 86_400, window: 604_800)]
        // The live provider's first publish has no limits, and so does every one while the token
        // is expired. The controller no longer touches the stored index on a publish; the user's
        // pick (track 3) must survive both, and so must the transport and Shuffle meanwhile.
        let none = UsageSnapshot(generatedAt: now)
        let full = UsageSnapshot(generatedAt: now, limits: three)
        let stored = 2
        c.check("no limits: no hero", HeroTrack.hero(in: none, index: stored) == nil)
        c.equal("next with no tracks keeps the pick", HeroTrack.step(stored, by: 1, count: none.limits.count), stored)
        c.equal("previous with no tracks keeps the pick", HeroTrack.previous(stored, count: 0), stored)
        c.equal("next() with no tracks keeps the pick", HeroTrack.next(stored, count: 0), stored)
        c.equal("limits back: track 3 is still the hero", HeroTrack.hero(in: full, index: stored)?.id,
                "weekly_scoped:Fable")
        c.equal("and the marquee numbers it 3", HeroTrack.trackNumber(index: stored, count: full.limits.count), 3)
        let two = UsageSnapshot(generatedAt: now, limits: Array(three.prefix(2)))
        c.equal("a briefly shorter tracklist wraps at use", HeroTrack.hero(in: two, index: stored)?.id, "session")
        c.equal("stepping still wraps forwards", HeroTrack.step(2, by: 1, count: 3), 0)
        c.equal("stepping still wraps backwards", HeroTrack.step(0, by: -1, count: 3), 2)
        c.equal("a stale out-of-range pick steps from where it shows", HeroTrack.step(5, by: 1, count: 3), 0)
    }

    // MARK: - 2. Limit alerts

    private static func limitAlerts(_ c: Checker, tmp: URL) {
        c.section("limit alerts: once per limit per window, across relaunches and outages")
        let suite = tmp.appendingPathComponent("alert-prefs-\(UUID().uuidString).plist").path
        guard let defaults = UserDefaults(suiteName: suite) else {
            c.skip("limit alerts", "could not open a scratch defaults domain")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)

        var fired: [String] = []
        func launch() -> ThresholdNotifier {
            ThresholdNotifier(prefs: prefs) { limit, threshold in fired.append("\(limit.id)@\(Int(threshold))") }
        }
        // A reset time with a microsecond fraction, the way the usage endpoint reports it.
        let reset = Date(timeIntervalSince1970: 1_790_010_000.123456)
        let now = reset - 3 * 3_600
        func snap(_ session: Double, jitter: TimeInterval = 0, week: Double = 20,
                  reset r: Date = reset) -> UsageSnapshot {
            UsageSnapshot(generatedAt: now, limits: [
                gauge("session", .session, session, resets: r + jitter),
                gauge("weekly_all", .weeklyAll, week, resets: reset + 4 * 86_400, window: 604_800),
            ])
        }
        let noLimits = UsageSnapshot(generatedAt: now)

        c.check("nothing is stored before the first launch", prefs.announcedAlerts == nil)
        let first = launch()
        first.check(snapshot: noLimits, now: now)
        first.check(snapshot: snap(80), now: now)
        c.equal("first launch: a limit already past 75 % is recorded, not announced", fired, [])
        first.check(snapshot: snap(91, jitter: 0.4), now: now)
        c.equal("crossing 90 % is announced", fired, ["session@90"])
        first.check(snapshot: snap(92, jitter: -0.3), now: now)
        c.equal("a reset time that moved by a fraction of a second is the same window", fired, ["session@90"])
        first.check(snapshot: noLimits, now: now)
        first.check(snapshot: snap(92), now: now)
        c.equal("an auth outage (no limits) does not wipe the record", fired, ["session@90"])
        c.check("the record is persisted",
                prefs.announcedAlerts?.contains("90|\(AlertLedger.window(of: reset)!)|session") == true)

        let second = launch()
        second.check(snapshot: noLimits, now: now)
        second.check(snapshot: snap(93, jitter: 0.2), now: now)
        c.equal("a relaunch does not announce again", fired, ["session@90"])
        second.check(snapshot: snap(100, week: 76), now: now)
        c.equal("crossing 100 % and another limit's 75 % are announced", fired.sorted(),
                ["session@100", "session@90", "weekly_all@75"])

        // The next session window: a new key, announced again; the old one is forgotten once over.
        fired = []
        let nextReset = reset + 5 * 3_600
        second.check(snapshot: snap(77, week: 76, reset: nextReset), now: reset + 120)
        c.equal("a new window announces again", fired, ["session@75"])
        let oldWindow = "|\(AlertLedger.window(of: reset)!)|session"
        c.check("a window that has ended is forgotten", !second.announced.contains { $0.hasSuffix(oldWindow) })

        // A reset time that straddles the rounding boundary (hh:mm:29.9, then hh:mm:30.1).
        var ledger = AlertLedger()
        let minute = Date(timeIntervalSince1970: 60 * 29_833_334)
        c.equal("first reading records 75", ledger.record(gauge("session", .session, 80, resets: minute + 29.9)), 75)
        c.equal("straddling the rounding boundary is the same window",
                ledger.record(gauge("session", .session, 80, resets: minute + 30.1)), nil)
        c.equal("the ledger round-trips through its stored form", AlertLedger(encoded: ledger.encoded), ledger)

        // Repeat switched on while no limits are known: the first snapshot with limits is recorded.
        fired = []
        let fresh = ThresholdNotifier(prefs: nil) { limit, threshold in fired.append("\(limit.id)@\(Int(threshold))") }
        fresh.prime(snapshot: noLimits)
        fresh.check(snapshot: snap(95), now: now)
        c.equal("priming with no limits primes on the next snapshot instead", fired, [])
    }

    // MARK: - 3. Scale per screen

    private static func scalePerScreen(_ c: Checker) {
        c.section("scale: the default follows the screen, not the scale in use")
        let retina = CGRect(x: 0, y: 0, width: 1920, height: 1200)     // HiDPI, 2x backing
        let plain = CGRect(x: 1920, y: 0, width: 2560, height: 1415)   // a 1x display
        let plainDefault = ScaleModel.defaultPointScale(visibleFrame: plain, backing: 1)

        // Nothing stored: a first-run 1.5x window visits the 1x display and comes back.
        c.equal("first run on the Retina screen", ScaleModel.resolved(stored: nil, visibleFrame: retina, backing: 2), 1.5)
        c.equal("on the 1x display: that display's own default",
                ScaleModel.resolved(stored: nil, visibleFrame: plain, backing: 1), plainDefault)
        c.equal("back on Retina: 1.5x again (the old rule kept the 1x display's 2x)",
                ScaleModel.resolved(stored: nil, visibleFrame: retina, backing: 2), 1.5)
        c.check("the default is valid where it is used", ScaleModel.isValid(plainDefault, backing: 1))

        // A stored preference is honoured where it can be and snapped where it cannot.
        c.equal("a stored 1.5x on a 1x display snaps", ScaleModel.resolved(stored: 1.5, visibleFrame: plain, backing: 1), 2)
        c.equal("and is 1.5x again back on Retina", ScaleModel.resolved(stored: 1.5, visibleFrame: retina, backing: 2), 1.5)
        c.equal("a stored 2x beats a screen default", ScaleModel.resolved(stored: 2, visibleFrame: retina, backing: 2), 2)
    }

    // MARK: - 4. Skin images whose headers claim gigabytes

    /// A 24-bit BMP header claiming `width x height`, followed by `pixelBytes` zero bytes - far
    /// fewer than it claims. ImageIO accepts such a truncated file and builds the full-size image
    /// from it: 100 KB of zeros (151 bytes deflated, a 270-byte `.wsz`) became 3.6 GB.
    static func bmpBomb(width: Int, height: Int, pixelBytes: Int = 100_000) -> Data {
        bmpHeader(width: width, height: height) + Data(count: pixelBytes)
    }

    /// A 24-bit BMP header claiming `width x height`, with no pixels behind it.
    static func bmpHeader(width: Int, height: Int) -> Data {
        var d = Data()
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let rowBytes = ((width * 3) + 3) & ~3
        d.append(contentsOf: [0x42, 0x4D])
        u32(UInt32(truncatingIfNeeded: 54 + rowBytes * height))
        u16(0); u16(0)
        u32(54)
        u32(40)
        u32(UInt32(width)); u32(UInt32(height))
        u16(1); u16(24)
        u32(0); u32(UInt32(truncatingIfNeeded: rowBytes * height))
        u32(2835); u32(2835)
        u32(0); u32(0)
        return d
    }

    /// An 8-bit grey PNG whose IHDR claims `width x height` but whose IDAT holds only `rows` rows
    /// (zeros, in stored deflate blocks). ImageIO accepts it and builds the full-size image.
    static func pngBomb(width: Int, height: Int, rows: Int = 2) -> Data {
        var d = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        func chunk(_ type: String, _ body: Data) {
            withUnsafeBytes(of: UInt32(body.count).bigEndian) { d.append(contentsOf: $0) }
            let typed = Data(type.utf8) + body
            d.append(typed)
            withUnsafeBytes(of: TestZip.crc32(typed).bigEndian) { d.append(contentsOf: $0) }
        }
        var ihdr = Data()
        withUnsafeBytes(of: UInt32(width).bigEndian) { ihdr.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(height).bigEndian) { ihdr.append(contentsOf: $0) }
        ihdr.append(contentsOf: [8, 0, 0, 0, 0])                       // 8-bit grey
        chunk("IHDR", ihdr)
        // zlib: header, stored blocks of zeros (filter byte 0 + zero pixels per row), Adler-32.
        let total = rows * (1 + width)
        var stream = Data([0x78, 0x01])
        var left = total
        while left > 0 {
            let n = min(left, 65_535)
            left -= n
            stream.append(left == 0 ? 1 : 0)
            withUnsafeBytes(of: UInt16(n).littleEndian) { stream.append(contentsOf: $0) }
            withUnsafeBytes(of: (~UInt16(n)).littleEndian) { stream.append(contentsOf: $0) }
            stream.append(Data(count: n))
        }
        let adler = (UInt32(total % 65_521) << 16) | 1                  // Adler-32 of all zeros
        withUnsafeBytes(of: adler.bigEndian) { stream.append(contentsOf: $0) }
        chunk("IDAT", stream)
        chunk("IEND", Data())
        return d
    }

    /// The size ImageIO reads from an image's header, without decoding it: proof that a fixture is
    /// a real bomb and not something ImageIO would refuse anyway.
    private static func headerSize(_ data: Data) -> SkinPair? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        return SkinPair(w, h)
    }

    private static func hostileSkinImages(_ c: Checker, tmp: URL) {
        c.section("skin images: a header claiming gigabytes is refused before decoding")
        let baseMain = Skin.base.rawSheet(.main)

        let bmp = bmpBomb(width: 30_000, height: 30_000)
        let png = pngBomb(width: 15_000, height: 15_000)
        let fontPNG = pngBomb(width: 16 * 1_000, height: 6 * 1_000, rows: 1)
        c.equal("the BMP fixture is a real bomb (ImageIO reads 30000x30000)", headerSize(bmp), SkinPair(30_000, 30_000))
        c.equal("the PNG fixture is a real bomb (ImageIO reads 15000x15000)", headerSize(png), SkinPair(15_000, 15_000))
        c.equal("so is the plfont one (16000x6000)", headerSize(fontPNG), SkinPair(16_000, 6_000))

        let bmpBombURL = tmp.appendingPathComponent("bmp-bomb.wsz")
        try? TestZip.make([("main.bmp", bmp)], dataDescriptor: false).write(to: bmpBombURL)
        if let skin = try? SkinLoader.load(url: bmpBombURL) {
            c.check("BMP bomb: the sheet is refused", !skin.hasOwnSheet(.main))
            c.check("BMP bomb: with a warning naming the claimed size",
                    skin.warnings.contains { $0.contains("main.bmp") && $0.contains("30000x30000") })
            c.check("BMP bomb: Base's main sheet stands in", baseMain != nil && skin.sheet(.main) === baseMain)
        } else {
            c.check("the BMP bomb archive still loads (with Base fallbacks)", false)
        }

        let pngBombURL = tmp.appendingPathComponent("png-bomb.wsz")
        try? TestZip.make([("MAIN.PNG", png), ("plfont.png", fontPNG)], dataDescriptor: false).write(to: pngBombURL)
        if let skin = try? SkinLoader.load(url: pngBombURL) {
            c.check("PNG bomb: the sheet is refused", !skin.hasOwnSheet(.main))
            c.check("PNG bomb: Base's main sheet stands in", baseMain != nil && skin.sheet(.main) === baseMain)
            c.check("PNG bomb: the plfont sheet is refused too", !skin.hasOwnPlaylistFont)
            c.check("PNG bomb: warned about both",
                    skin.warnings.contains { $0.contains("15000x15000") }
                    && skin.warnings.contains { $0.hasPrefix("plfont") && $0.contains("16000x6000") })
        } else {
            c.check("the PNG bomb archive still loads (with Base fallbacks)", false)
        }

        // Generous: a sheet drawn at 4x its spec size is still taken; one pixel more is not.
        let spec = SkinSpec.sheets[.cbuttons]!
        let limit = SkinLoader.pixelLimit(for: spec)
        c.equal("cbuttons may be 4x wide, and 512 px tall at least", limit, SkinPair(4 * spec.width, 512))
        let big = tmp.appendingPathComponent("big-sheets.wsz")
        try? TestZip.make([("cbuttons.bmp", makeBMPData(width: limit.w, height: 4 * spec.height, colour: (9, 9, 9))),
                           ("shufrep.bmp", bmpBomb(width: SkinLoader.pixelLimit(for: SkinSpec.sheets[.shufrep]!).w + 1,
                                                   height: 85, pixelBytes: 1_000))],
                          dataDescriptor: false).write(to: big)
        if let skin = try? SkinLoader.load(url: big) {
            c.check("a 4x sheet loads", skin.hasOwnSheet(.cbuttons))
            c.check("one pixel over the limit is refused", !skin.hasOwnSheet(.shufrep))
        } else {
            c.check("the 4x skin loads", false)
        }

        // A plain-folder skin gets the archive's per-file bound, checked before the file is read.
        // A sparse file: 64 MiB + 1 on paper, nothing on disk.
        let dir = tmp.appendingPathComponent("HugeFileSkin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let huge = dir.appendingPathComponent("main.bmp")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        if let h = FileHandle(forWritingAtPath: huge.path) {
            try? h.truncate(atOffset: UInt64(ZipArchive.maximumMemberBytes + 1))
            try? h.close()
        }
        try? "0,0,0\n".write(to: dir.appendingPathComponent("viscolor.txt"), atomically: true, encoding: .utf8)
        if let skin = try? SkinLoader.load(url: dir) {
            c.check("an oversized file in a folder skin is not read", !skin.hasOwnSheet(.main))
            c.check("and says why", skin.warnings.contains { $0.contains("main.bmp") && $0.contains("bytes") })
        } else {
            c.check("the folder skin with an oversized file still loads", false)
        }
    }

    private static func skinInstall(_ c: Checker, tmp: URL) {
        c.section("skin install: validated first, never leaves a copy behind")
        let fm = FileManager.default
        let skins = tmp.appendingPathComponent("UserSkins", isDirectory: true)
        try? fm.createDirectory(at: skins, withIntermediateDirectories: true)
        func contents() -> [String] {
            ((try? fm.contentsOfDirectory(atPath: skins.path)) ?? []).sorted()
        }

        let garbage = tmp.appendingPathComponent("Broken.wsz")
        try? Data(repeating: 0x55, count: 2_048).write(to: garbage)
        c.check("a skin that does not load is refused", (try? SkinCatalog.install(garbage, into: skins)) == nil)
        c.equal("and nothing was copied", contents(), [])

        let good = tmp.appendingPathComponent("drop", isDirectory: true).appendingPathComponent("Fine", isDirectory: true)
        try? fm.createDirectory(at: good, withIntermediateDirectories: true)
        writeBMPFile(good.appendingPathComponent("main.bmp"), colour: (1, 2, 3))
        let installed = try? SkinCatalog.install(good, into: skins)
        c.equal("a good skin is installed under its own name", installed?.url.lastPathComponent, "Fine")
        c.equal("with no staging copy left over", contents(), ["Fine"])
        c.check("the returned skin is the one that was loaded", installed?.skin.hasOwnSheet(.main) == true)

        // A broken skin with the same name must not take the installed one's place.
        let brokenTwin = tmp.appendingPathComponent("drop2", isDirectory: true).appendingPathComponent("Fine", isDirectory: true)
        try? fm.createDirectory(at: brokenTwin, withIntermediateDirectories: true)
        c.check("a broken skin of the same name is refused", (try? SkinCatalog.install(brokenTwin, into: skins)) == nil)
        c.check("and the installed one is untouched",
                fm.fileExists(atPath: skins.appendingPathComponent("Fine/main.bmp").path) && contents() == ["Fine"])

        // A good skin of the same name replaces it.
        writeBMPFile(brokenTwin.appendingPathComponent("main.bmp"), colour: (7, 8, 9))
        let replaced = try? SkinCatalog.install(brokenTwin, into: skins)
        let now = try? Data(contentsOf: skins.appendingPathComponent("Fine/main.bmp"))
        c.check("a good skin of the same name replaces it",
                replaced?.url.lastPathComponent == "Fine"
                && now == makeBMPData(width: 275, height: 116, colour: (7, 8, 9)))
        c.equal("still one skin, no leftovers", contents(), ["Fine"])
    }

    private static func writeBMPFile(_ url: URL, colour: (UInt8, UInt8, UInt8)) {
        try? makeBMPData(width: 275, height: 116, colour: colour).write(to: url)
    }

    // MARK: - 5. The Sessions list

    private static func sessionsListState(_ c: Checker) {
        c.section("Sessions list: scroll and selection survive updates")
        var list = SessionListState()
        var ids = (0..<20).map { "s\($0)" }
        list.setScroll(15, count: ids.count, visibleRows: 13)
        c.equal("scroll stops at the last page", list.scroll, 7)
        list.select(index: 9, in: ids)
        c.equal("a click selects that row's session", list.selectedID, "s9")

        // The list re-sorts by activity: s9 was just used and moves to the top.
        ids = ["s9"] + ids.filter { $0 != "s9" }
        list.reconcile(ids: ids, visibleRows: 13)
        c.equal("the selection follows its session through a re-sort", list.selectedIndex(in: ids), 0)

        // The list shrinks, and the selected session is no longer in it.
        ids = ["s1", "s2", "s3", "s4", "s5"]
        c.check("an update that changes something says so", list.reconcile(ids: ids, visibleRows: 13))
        c.equal("scroll is re-clamped when the list shrinks", list.scroll, 0)
        c.check("a session that is gone takes the selection with it",
                list.selectedID == nil && list.selectedIndex(in: ids) == nil)
        c.check("an update that changes nothing says so", !list.reconcile(ids: ids, visibleRows: 13))
        list.select(index: 7, in: ids)
        c.check("selecting past the end selects nothing", list.selectedID == nil)

        // The partial strip under the last whole row is not a row. 232 px at an 11 px pitch:
        // 174 px of list, 15 whole rows, a 9 px strip below.
        let strip = CGPoint(x: 100, y: 20 + 15 * 11 + 3)
        c.equal("a click on the strip under the last row selects nothing",
                PlaylistRenderer.rowIndex(at: strip, width: 275, height: 232, scroll: 0, count: 40, rowHeight: 11), nil)
        c.equal("the last whole row still hits",
                PlaylistRenderer.rowIndex(at: CGPoint(x: 100, y: 20 + 14 * 11 + 1), width: 275, height: 232,
                                          scroll: 0, count: 40, rowHeight: 11), 14)
        c.equal("scrolled, too",
                PlaylistRenderer.rowIndex(at: strip, width: 275, height: 232, scroll: 5, count: 40, rowHeight: 11), nil)
    }

    // MARK: - 7. Docking on the art rectangle

    /// The art rectangle of a window of `skin` pixels at `scale` whose top-left is `topLeft`.
    private static func art(_ topLeft: CGPoint, _ skin: SkinPair, _ scale: Double) -> CGRect {
        let size = ScaleModel.contentSize(skin: skin, points: scale)
        let frame = CGRect(origin: WindowLayout.origin(topLeft: topLeft, height: size.height), size: size)
        return WindowLayout.skinRect(frame: frame, skinSize: skin, scale: scale)
    }

    private static func dockingOnTheArt(_ c: Checker) {
        c.section("docking: on the art, not on the ceil()ed frame, and never a seam (SPEC 2.8)")
        let sessions = SkinPair(Layout.Playlist.defaultSize.w, Layout.Playlist.defaultSize.h + 29)   // 261 px
        let field = Layout.Field.defaultSize
        let top = CGPoint(x: 100, y: 1_000)

        let mainArt = art(top, Layout.Main.size, 1.5)
        c.equal("the main window's art is 412.5 pt wide (in a 413 pt window)", mainArt.width, 412.5)
        let slFrameSize = ScaleModel.contentSize(skin: sessions, points: 1.5)
        let slFrame = CGRect(origin: WindowLayout.origin(topLeft: CGPoint(x: 100, y: mainArt.minY),
                                                         height: slFrameSize.height), size: slFrameSize)
        let slArt = WindowLayout.skinRect(frame: slFrame, skinSize: sessions, scale: 1.5)
        c.equal("261 px of Sessions is 391.5 pt of art", slArt.height, 391.5)
        c.equal("in a 392 pt window", slFrame.height, 392)
        c.equal("the art shares the frame's top-left", WindowLayout.topLeft(of: slArt), WindowLayout.topLeft(of: slFrame))

        // AppKit floors a half-point window origin, so a half-point art edge is met by rounding
        // towards the neighbour: the arts overlap by half a point instead of leaving a gap.
        let fieldArt = ScaleModel.exactSize(skin: field, points: 1.5)
        let fieldFrame = ScaleModel.contentSize(skin: field, points: 1.5)
        let near = CGRect(x: 103, y: slArt.minY - fieldArt.height - 5, width: fieldArt.width, height: fieldArt.height)
        let snapped = Docking.snap(frame: near, to: [mainArt, slArt], screen: nil,
                                   threshold: Docking.threshold(scale: 1.5))
        c.equal("Token Flow's art snaps to Sessions' art edge", snapped.y + fieldArt.height, slArt.minY)
        let origin = WindowLayout.wholePointOrigin(art: CGRect(origin: snapped, size: fieldArt),
                                                   frameHeight: fieldFrame.height, neighbours: [mainArt, slArt])
        c.check("its window lands on whole points", origin.x == origin.x.rounded() && origin.y == origin.y.rounded())
        c.close("rounded up into Sessions: half a point (one device pixel) of overlap, no seam",
                Double(origin.y + fieldFrame.height - slArt.minY), 0.5)
        // What docking on the frames did: the ceil()ed 392 pt put Token Flow's top half a point -
        // one see-through device pixel at 2x backing - under Sessions' art.
        let onFrames = Docking.snap(frame: CGRect(origin: near.origin, size: fieldFrame), to: [slFrame], screen: nil,
                                    threshold: Docking.threshold(scale: 1.5))
        c.close("(on the frames it left that seam)", Double(slArt.minY - (onFrames.y + fieldFrame.height)), 0.5)

        // The rounding rule on its own: towards the neighbour, floored when there is none.
        let block = CGRect(x: 0, y: 100, width: 50, height: 50)
        let halfBlock = CGRect(x: 0, y: 100.5, width: 50, height: 49.5)                  // its art ends on a half point
        let under = CGRect(x: 0, y: 100.5 - 10, width: 50, height: 10)
        c.equal("hanging under a half-point edge rounds up into it",
                WindowLayout.wholePointOrigin(art: under, frameHeight: 10, neighbours: [halfBlock]), CGPoint(x: 0, y: 91))
        c.equal("alone, it floors like AppKit",
                WindowLayout.wholePointOrigin(art: under, frameHeight: 10, neighbours: []), CGPoint(x: 0, y: 90))
        c.equal("left of a neighbour rounds right",
                WindowLayout.wholePointOrigin(art: CGRect(x: -20.5, y: 100, width: 20.5, height: 50), frameHeight: 50,
                                              neighbours: [block]), CGPoint(x: -20, y: 100))
        c.equal("right of a neighbour rounds left",
                WindowLayout.wholePointOrigin(art: CGRect(x: 50.5, y: 100, width: 20, height: 50), frameHeight: 50,
                                              neighbours: [CGRect(x: 0, y: 100, width: 50.5, height: 50)]),
                CGPoint(x: 50, y: 100))

        // The default column: main, Sessions (261 px), Token Flow, EQ at 1.5x.
        let column = Docking.column(topLeft: CGPoint(x: 40, y: 1_040), scale: 1.5,
                                    skinSizes: [Layout.Main.size, sessions, field, Layout.EQ.size])
        c.equal("default column corners, on whole points", column,
                [CGPoint(x: 40, y: 1_040), CGPoint(x: 40, y: 866), CGPoint(x: 40, y: 475), CGPoint(x: 40, y: 127)])
        let arts = zip(column, [Layout.Main.size, sessions, field, Layout.EQ.size]).map { art($0, $1, 1.5) }
        c.check("every window in the column touches or overlaps the one above by at most a device pixel",
                zip(arts, arts.dropFirst()).allSatisfy { upper, lower in
                    let overlap = lower.maxY - upper.minY
                    return overlap >= 0 && overlap <= 0.5
                })

        // A scale change re-lays out the group on the art, too: 2x -> 1.5x -> 2x.
        let main2 = art(top, Layout.Main.size, 2)
        let sl2 = art(CGPoint(x: 100, y: main2.minY), sessions, 2)
        let tf2 = art(CGPoint(x: 100, y: sl2.minY), field, 2)
        let eq2 = art(CGPoint(x: main2.maxX, y: main2.maxY), Layout.EQ.size, 2)          // docked at the side
        let parked = art(CGPoint(x: 1_500, y: 400), Layout.EQ.size, 2)                    // not docked
        let members = [Docking.GroupMember(rect: sl2, skinSize: sessions, isDocked: true),
                       Docking.GroupMember(rect: tf2, skinSize: field, isDocked: true),
                       Docking.GroupMember(rect: eq2, skinSize: Layout.EQ.size, isDocked: true),
                       Docking.GroupMember(rect: parked, skinSize: Layout.EQ.size, isDocked: false)]
        let main15 = art(top, Layout.Main.size, 1.5)
        let at15 = Docking.relayout(main: main2, to: main15, scale: 2, to: 1.5, members: members)
        c.equal("Sessions goes under the main window", at15[0], CGPoint(x: 100, y: main15.minY))
        c.equal("Token Flow goes under Sessions' 391.5 pt of art, rounded up into it",
                at15[1], CGPoint(x: 100, y: (main15.minY - 391.5).rounded(.up)))
        c.equal("a window docked at the side keeps its offset, rounded left into the main window",
                at15[2], CGPoint(x: (100 + 412.5).rounded(.down), y: 1_000))
        c.check("a parked window is left alone", at15[3] == nil)

        let sl15 = art(at15[0]!, sessions, 1.5)
        let tf15 = art(at15[1]!, field, 1.5)
        let eq15 = art(at15[2]!, Layout.EQ.size, 1.5)
        c.check("the group is still one docked group", Docking.dockedGroup(anchor: main15, frames: [sl15, tf15, eq15]) == [0, 1, 2])
        let back = Docking.relayout(main: main15, to: main2, scale: 1.5, to: 2, members: [
            Docking.GroupMember(rect: sl15, skinSize: sessions, isDocked: true),
            Docking.GroupMember(rect: tf15, skinSize: field, isDocked: true),
            Docking.GroupMember(rect: eq15, skinSize: Layout.EQ.size, isDocked: true),
        ])
        let started: [CGPoint?] = [WindowLayout.topLeft(of: sl2), WindowLayout.topLeft(of: tf2),
                                   WindowLayout.topLeft(of: eq2)]
        c.equal("and back at 2x, everything is exactly where it started", [back[0], back[1], back[2]], started)
    }

    // MARK: - 8. Sessions auto-fit (SPEC 2.4, amendment A7)

    private static func sessionsAutoFit(_ c: Checker) {
        c.section("Sessions auto-fit: the smallest valid height that shows every session (A7)")
        let minH = Layout.Playlist.minSize.h
        let step = Layout.Playlist.resizeStep.h
        c.equal("no sessions: the minimum height", PlaylistFit.height(count: 0, rowHeight: 13), minH)
        c.equal("four rows fit the minimum", PlaylistFit.height(count: 4, rowHeight: 13), minH)
        c.equal("a fifth takes one step", PlaylistFit.height(count: 5, rowHeight: 13), minH + step)
        c.equal("thirteen fit the old default", PlaylistFit.height(count: 13, rowHeight: 13),
                Layout.Playlist.defaultSize.h)
        c.equal("one more than fits takes the next step", PlaylistFit.height(count: 14, rowHeight: 13),
                Layout.Playlist.defaultSize.h + step)
        // 435 px has a 377 px list: exactly 29 rows of 13, no strip under the last one.
        c.equal("an exact multiple: 29 rows fill 435 px to the pixel", PlaylistFit.height(count: 29, rowHeight: 13), 435)
        c.equal("and the thirtieth row needs the next step", PlaylistFit.height(count: 30, rowHeight: 13), 464)
        // The skin's plfont sets the pitch (SPEC 3.2): Walnut 76 draws 12 px rows.
        c.equal("8 sessions at a 12 px pitch", PlaylistFit.height(count: 8, rowHeight: 12), 174)
        c.equal("15 sessions at an 11 px pitch fit the old default", PlaylistFit.height(count: 15, rowHeight: 11), 232)
        c.equal("3 sessions at a 20 px pitch", PlaylistFit.height(count: 3, rowHeight: 20), minH + step)
        c.equal("a nonsense pitch cannot divide by zero", PlaylistFit.height(count: 3, rowHeight: 0), minH)
        c.equal("a negative count is no sessions", PlaylistFit.height(count: -2, rowHeight: 13), minH)

        // The cap: the largest valid height within it, never below the minimum.
        c.equal("a cap between steps rounds down to a step", PlaylistFit.height(count: 30, rowHeight: 13, maxHeight: 300), 290)
        c.equal("a cap on a step is that step", PlaylistFit.height(count: 30, rowHeight: 13, maxHeight: 290), 290)
        c.equal("a cap above the fit changes nothing", PlaylistFit.height(count: 8, rowHeight: 12, maxHeight: 1_000), 174)
        c.equal("a cap below the minimum still gets the minimum",
                PlaylistFit.height(count: 30, rowHeight: 13, maxHeight: 50), minH)
        c.equal("so does a negative cap (the column is already off screen)",
                PlaylistFit.height(count: 30, rowHeight: 13, maxHeight: -400), minH)

        // Against the renderer's own arithmetic, for every count and pitch in a wide range: the
        // fit is a height the grip could produce, it shows every row, and one step less does not.
        var agrees = true
        for rowHeight in 6...24 {
            for count in 0...60 {
                let h = PlaylistFit.height(count: count, rowHeight: rowHeight)
                let shows = PlaylistRenderer.visibleRows(height: h, rowHeight: rowHeight) >= count
                let smallest = h == minH || PlaylistRenderer.visibleRows(height: h - step, rowHeight: rowHeight) < count
                if PlaylistRenderer.snapHeight(h) != h || !shows || !smallest { agrees = false }
            }
        }
        c.check("agrees with snapHeight and visibleRows for 0...60 rows at 6...24 px", agrees)

        // The screen cap, on art rectangles (SPEC 2.8). Sessions hangs from y = 1000.
        let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_200)
        let sl2 = art(CGPoint(x: 100, y: 1_000), Layout.Playlist.defaultSize, 2)
        c.equal("alone, it may reach the bottom of the screen",
                PlaylistFit.maxHeight(art: sl2, below: [], screen: screen, scale: 2), 500)
        c.equal("the Dock's edge is the bottom",
                PlaylistFit.maxHeight(art: sl2, below: [], screen: CGRect(x: 0, y: 70, width: 1_920, height: 1_130),
                                      scale: 2), 465)
        let tf2 = art(CGPoint(x: 100, y: sl2.minY), Layout.Field.defaultSize, 2)
        let cap2 = PlaylistFit.maxHeight(art: sl2, below: [tf2], screen: screen, scale: 2)
        c.equal("Token Flow hanging under it takes its 464 pt off the room", cap2, 268)
        c.equal("so 30 sessions stop at the step below the cap",
                PlaylistFit.height(count: 30, rowHeight: 13, maxHeight: cap2), 261)

        // At 1.5x the answer is exact, not a point short: Token Flow hangs rounded up into a
        // half-point edge, and at 435 px it lands with its bottom exactly on the screen's.
        let sessions261 = SkinPair(Layout.Playlist.defaultSize.w, 261)
        let column = Docking.column(topLeft: CGPoint(x: 100, y: 1_000), scale: 1.5,
                                    skinSizes: [sessions261, Layout.Field.defaultSize])
        let sl15 = art(column[0], sessions261, 1.5)
        let tf15 = art(column[1], Layout.Field.defaultSize, 1.5)
        let cap15 = PlaylistFit.maxHeight(art: sl15, below: [tf15], screen: screen, scale: 1.5)
        c.equal("at 1.5x the cap is 435 px", cap15, 435)
        let grown = art(column[0], SkinPair(Layout.Playlist.defaultSize.w, cap15), 1.5)
        c.equal("and there Token Flow's bottom is exactly on the screen's",
                tf15.minY + Docking.followingShift(from: sl15.minY, to: grown.minY), screen.minY)
        let over = art(column[0], SkinPair(Layout.Playlist.defaultSize.w, cap15 + 1), 1.5)
        c.check("one pixel more would push it off",
                tf15.minY + Docking.followingShift(from: sl15.minY, to: over.minY) < screen.minY)
        let lowScreen = CGRect(x: 0, y: 700, width: 1_920, height: 500)
        c.equal("a column already hanging off the screen caps below the minimum, and gets the minimum",
                PlaylistFit.height(count: 8, rowHeight: 13,
                                   maxHeight: PlaylistFit.maxHeight(art: sl2, below: [tf2], screen: lowScreen, scale: 2)),
                minH)
    }

    // MARK: - 9. The windows docked below Sessions follow its height (A7)

    private static func dockedBelowFollowsHeight(_ c: Checker) {
        c.section("docking: what is docked below Sessions follows its height, and nothing else moves (A7)")
        let top = CGPoint(x: 100, y: 1_000)
        let mainArt = art(top, Layout.Main.size, 2)
        let sl = art(CGPoint(x: 100, y: mainArt.minY), Layout.Playlist.defaultSize, 2)
        let tf = art(CGPoint(x: 100, y: sl.minY), Layout.Field.defaultSize, 2)
        let eqUnder = art(CGPoint(x: 100, y: tf.minY), Layout.EQ.size, 2)
        let besideTF = art(CGPoint(x: tf.maxX, y: tf.maxY), Layout.EQ.size, 2)
        let besideSessions = art(CGPoint(x: sl.maxX, y: sl.maxY), Layout.EQ.size, 2)
        let parked = art(CGPoint(x: 1_500, y: 300), Layout.EQ.size, 2)

        let frames = [mainArt, tf, eqUnder, besideTF, besideSessions, parked]
        let below = Docking.dockedBelow(sl, frames: frames)
        c.equal("the column under it, and what is docked beside that, follow", below, [1, 2, 3])
        c.check("the main window above it stays", !below.contains(0))
        c.check("a window beside it stays", !below.contains(4))
        c.check("a parked window stays", !below.contains(5))
        c.check("with nothing under it, nothing follows",
                Docking.dockedBelow(sl, frames: [mainArt, besideSessions, parked]).isEmpty)

        // A second column docked at the main window's side: a tall Token Flow beside both, and the
        // equalizer under it lying wholly below Sessions' bottom edge. It hangs from Token Flow,
        // which does not move, not from Sessions.
        let colB = art(CGPoint(x: mainArt.maxX, y: mainArt.maxY), SkinPair(Layout.Field.defaultSize.w, 377), 2)
        let colBFoot = art(CGPoint(x: colB.minX, y: colB.minY), Layout.EQ.size, 2)
        c.check("(the second column's foot is lower than Sessions' bottom)", colBFoot.maxY < sl.minY)
        c.check("a second column hanging from the main window stays",
                Docking.dockedBelow(sl, frames: [mainArt, colB, colBFoot]).isEmpty)
        // Sessions at the top of a column: the main window docked under it is below it.
        let slTop = art(top, Layout.Playlist.defaultSize, 2)
        let mainUnder = art(CGPoint(x: 100, y: slTop.minY), Layout.Main.size, 2)
        c.equal("a main window hanging under Sessions follows it", Docking.dockedBelow(slTop, frames: [mainUnder]), [0])

        // The shift: whole points, the bottom edge rounded up either side (A6).
        c.equal("2x, one step taller: down 58 pt", Docking.followingShift(from: 536, to: 478), -58)
        c.equal("2x, one step shorter: up 58 pt", Docking.followingShift(from: 478, to: 536), 58)
        c.equal("1.5x onto a whole point: down 44 pt, flush", Docking.followingShift(from: 608.5, to: 565), -44)
        c.equal("1.5x onto a half point: up 44 pt, one device pixel into it",
                Docking.followingShift(from: 565, to: 608.5), 44)
        c.equal("no height change, no move", Docking.followingShift(from: 608.5, to: 608.5), 0)

        // Walk Sessions through a run of heights at 1.5x with Token Flow and the equalizer hanging
        // under it: at every step Token Flow touches Sessions or overlaps it by one device pixel at
        // most, never gaps; the equalizer keeps its place under Token Flow; the main window above
        // never moves. Back at the first height, everything is exactly where it started.
        let sizes = [Layout.Main.size, SkinPair(Layout.Playlist.defaultSize.w, 261), Layout.Field.defaultSize,
                     Layout.EQ.size]
        let corners = Docking.column(topLeft: CGPoint(x: 40, y: 1_040), scale: 1.5, skinSizes: sizes)
        let fixedMain = art(corners[0], sizes[0], 1.5)
        var slArt = art(corners[1], sizes[1], 1.5)
        var others = [fixedMain, art(corners[2], sizes[2], 1.5), art(corners[3], sizes[3], 1.5)]
        let started = others
        var flush = true
        var together = true
        for h in [290, 319, 232, 116, 145, 435, 261] {
            let now = art(corners[1], SkinPair(Layout.Playlist.defaultSize.w, h), 1.5)
            let shift = Docking.followingShift(from: slArt.minY, to: now.minY)
            for i in Docking.dockedBelow(slArt, frames: others) { others[i] = others[i].offsetBy(dx: 0, dy: shift) }
            slArt = now
            let overlap = others[1].maxY - slArt.minY
            if overlap < 0 || overlap > 0.5 || shift != shift.rounded() { flush = false }
            if others[2].maxY - others[1].minY != started[2].maxY - started[1].minY { together = false }
        }
        c.check("every step: flush or one device pixel of overlap, by whole points", flush)
        c.check("Token Flow and the equalizer move as one", together)
        c.equal("the main window never moved", others[0], fixedMain)
        c.equal("back at 261 px, everything is where it started", others, started)
    }
}
