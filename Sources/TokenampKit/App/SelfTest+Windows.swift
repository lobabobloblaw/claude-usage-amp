import CoreGraphics
import Foundation

/// Window persistence and the off-screen rescue (SPEC 2.6, 2.7): the checks for the shade strip
/// that climbed the screen on every relaunch, and for the layout that stayed on an unplugged
/// display. Pure geometry, so no window is ever created.
extension SelfTest {

    static func windowPositions(_ c: Checker, tmp: URL) {
        c.section("window positions: top-left corners, migration, off-screen rescue")
        cornerGeometry(c)
        shadeRoundTrip(c)
        shadeToggleRoundTrip(c)
        unshadedRoundTrip(c)
        legacyMigration(c)
        storedFormat(c, tmp: tmp)
        offScreenRescue(c)
        // Placement on the screens there are: SelfTest+Placement.swift.
        windowPlacement(c)
    }

    // MARK: - A launch, step for step

    /// What `TokenampController.start` does with stored corners: every window is born at its full
    /// size, put at its corner (`SkinWindow.setTopLeft`, snapped to the device-pixel grid), and
    /// then the main window is shaded around its top-left (`SkinWindow.setSkinSize`).
    /// `skinHeights` are the unshaded heights, main first.
    private static func launch(corners: [CGPoint], skinHeights: [Int], shaded: Bool,
                               scale: Double, backing: CGFloat) -> [CGRect] {
        var frames = zip(corners, skinHeights).map { corner, h -> CGRect in
            let size = ScaleModel.contentSize(skin: SkinPair(275, h), points: scale)
            let origin = WindowLayout.origin(topLeft: corner, height: size.height)
            return CGRect(origin: SkinWindow.deviceAligned(origin, backing: backing), size: size)
        }
        if shaded {
            frames[0] = WindowLayout.resized(frames[0],
                                             to: ScaleModel.contentSize(skin: Layout.Shade.size, points: scale))
        }
        return frames
    }

    /// What quitting stores.
    private static func corners(_ frames: [CGRect]) -> [CGPoint] {
        frames.map { WindowLayout.topLeft(of: $0) }
    }

    /// A flush column under `top`, with the main window shaded or not: the layout a user docks.
    private static func column(top: CGPoint, skinHeights: [Int], shaded: Bool, scale: Double) -> [CGRect] {
        var out: [CGRect] = []
        var y = top.y
        for (i, h) in skinHeights.enumerated() {
            let skinH = i == 0 ? WindowLayout.mainSkinHeight(shaded: shaded) : h
            let size = ScaleModel.contentSize(skin: SkinPair(275, skinH), points: scale)
            out.append(CGRect(x: top.x, y: y - size.height, width: size.width, height: size.height))
            y -= size.height
        }
        return out
    }

    // MARK: - Corners

    private static func cornerGeometry(_ c: Checker) {
        let f = CGRect(x: 100, y: 500, width: 413, height: 174)
        c.equal("top-left of a frame", WindowLayout.topLeft(of: f), CGPoint(x: 100, y: 674))
        c.equal("origin from a top-left", WindowLayout.origin(topLeft: CGPoint(x: 100, y: 674), height: 174),
                CGPoint(x: 100, y: 500))
        for s in [1.0, 1.5, 2.0, 2.5, 3.0] {
            let full = CGRect(origin: CGPoint(x: 10, y: 300),
                              size: ScaleModel.contentSize(skin: Layout.Main.size, points: s))
            let strip = WindowLayout.resized(full, to: ScaleModel.contentSize(skin: Layout.Shade.size, points: s))
            c.equal("shade keeps the top-left at \(s)x", WindowLayout.topLeft(of: strip), WindowLayout.topLeft(of: full))
            c.equal("unshade keeps the top-left at \(s)x",
                    WindowLayout.topLeft(of: WindowLayout.resized(strip, to: full.size)), WindowLayout.topLeft(of: full))
        }
        c.equal("window height is ceil(skin x scale)", WindowLayout.windowHeight(skinHeight: 145, scale: 1.5), 218)
        c.equal("shade strip is 14 skin px", WindowLayout.mainSkinHeight(shaded: true), 14)
        c.equal("main window is 116 skin px", WindowLayout.mainSkinHeight(shaded: false), 116)

        // A window flush with the top of a screen whose menu bar hides: its corner is on the
        // screen's top edge, which `contains` excludes; the probe point is inside.
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let corner = CGPoint(x: 100, y: 1080)
        c.check("a corner on the top edge is not 'contained'", !screen.contains(corner))
        c.check("the probe point finds the screen", screen.contains(WindowLayout.probePoint(topLeft: corner)))
    }

    // MARK: - Bug: the shaded main window climbed the screen on every relaunch

    private static func shadeRoundTrip(_ c: Checker) {
        let heights = [Layout.Main.size.h, 232, 232]  // main, Sessions, Token Flow
        for s in [1.0, 1.5, 2.0] {
            let atQuit = column(top: CGPoint(x: 300, y: 1000), skinHeights: heights, shaded: true, scale: s)
            var frames = atQuit
            for _ in 0..<3 {
                frames = launch(corners: corners(frames), skinHeights: heights, shaded: true, scale: s, backing: 2)
            }
            c.equal("shaded \(s)x: strip is where it was after 3 relaunches", frames[0], atQuit[0])
            c.equal("shaded \(s)x: Sessions is where it was", frames[1], atQuit[1])
            c.equal("shaded \(s)x: Token Flow is where it was", frames[2], atQuit[2])
            c.close("shaded \(s)x: Sessions still hangs from the strip", Double(frames[1].maxY), Double(frames[0].minY))
            c.check("shaded \(s)x: strip and Sessions still docked", Docking.isAdjacent(frames[0], frames[1]))

            // The model reproduces the bug under the old scheme (a bottom-left origin, applied to
            // the full-height window before shading), so these checks would have caught it.
            let full = ScaleModel.contentSize(skin: Layout.Main.size, points: s)
            let oldStrip = WindowLayout.resized(CGRect(origin: atQuit[0].origin, size: full),
                                                to: atQuit[0].size)
            c.close("shaded \(s)x: a bottom-left origin would climb (116-14) x scale",
                    Double(oldStrip.minY - atQuit[0].minY), Double(116 - 14) * s)
        }
    }

    /// Relaunch after toggling shade off, then on again: each state comes back exactly.
    private static func shadeToggleRoundTrip(_ c: Checker) {
        let heights = [Layout.Main.size.h, 174, 232]
        for s in [1.0, 1.5, 2.0] {
            let shaded = column(top: CGPoint(x: 612, y: 988), skinHeights: heights, shaded: true, scale: s)
            // Shade off in the session: the main window grows down from its corner and the docked
            // windows re-hang below it (`DockingManager.relayoutDocked`).
            var open = shaded
            open[0] = WindowLayout.resized(shaded[0], to: ScaleModel.contentSize(skin: Layout.Main.size, points: s))
            open[1].origin.y = open[0].minY - open[1].height
            open[2].origin.y = open[1].minY - open[2].height
            let afterOff = launch(corners: corners(open), skinHeights: heights, shaded: false, scale: s, backing: 2)
            c.equal("toggled off \(s)x: relaunch restores every window", afterOff, open)

            // And on again: back to the strip, docked windows back up under it.
            var closed = afterOff
            closed[0] = WindowLayout.resized(afterOff[0], to: ScaleModel.contentSize(skin: Layout.Shade.size, points: s))
            closed[1].origin.y = closed[0].minY - closed[1].height
            closed[2].origin.y = closed[1].minY - closed[2].height
            let afterOn = launch(corners: corners(closed), skinHeights: heights, shaded: true, scale: s, backing: 2)
            c.equal("toggled on \(s)x: relaunch restores every window", afterOn, closed)
            c.equal("toggled off and on \(s)x: the strip never moved", afterOn[0], shaded[0])
        }
    }

    private static func unshadedRoundTrip(_ c: Checker) {
        // 145 skin px at 1.5x is 217.5 pt, a 218-pt window: the ceil must not make it drift.
        let heights = [Layout.Main.size.h, 145, 145]
        for (s, backing) in [(1.0, CGFloat(1)), (1.5, CGFloat(2)), (2.0, CGFloat(2)), (3.0, CGFloat(1))] {
            let atQuit = column(top: CGPoint(x: 41.5, y: 877.5), skinHeights: heights, shaded: false, scale: s)
                .map { CGRect(origin: SkinWindow.deviceAligned($0.origin, backing: backing), size: $0.size) }
            var frames = atQuit
            for _ in 0..<3 {
                frames = launch(corners: corners(frames), skinHeights: heights, shaded: false, scale: s, backing: backing)
            }
            c.equal("unshaded \(s)x on a \(Int(backing))x screen: 3 relaunches restore every window",
                    frames, atQuit)
        }
    }

    // MARK: - Migration of the bottom-left origins earlier builds stored

    private static func legacyMigration(_ c: Checker) {
        // Unshaded at 1.5x: the old origin plus the 174-pt window height.
        let main = WindowLayout.migratedTopLeft(legacyOrigin: CGPoint(x: 100, y: 500),
                                                skinHeight: WindowLayout.mainSkinHeight(shaded: false), scale: 1.5)
        c.equal("legacy main origin -> corner (unshaded, 1.5x)", main, CGPoint(x: 100, y: 674))
        // Quit shaded at 2x: the origin was the strip's, 28 pt tall.
        let strip = WindowLayout.migratedTopLeft(legacyOrigin: CGPoint(x: 100, y: 800),
                                                 skinHeight: WindowLayout.mainSkinHeight(shaded: true), scale: 2)
        c.equal("legacy strip origin -> corner (shaded, 2x)", strip, CGPoint(x: 100, y: 828))
        // Sessions at 145 skin px and 1.5x: a 218-pt window.
        let sessions = WindowLayout.migratedTopLeft(legacyOrigin: CGPoint(x: 100, y: 282), skinHeight: 145, scale: 1.5)
        c.equal("legacy Sessions origin -> corner (145 px, 1.5x)", sessions, CGPoint(x: 100, y: 500))

        // The first launch after the update puts every window exactly where the old build left it.
        for (shaded, s) in [(false, 1.0), (true, 1.0), (false, 1.5), (true, 2.0)] {
            let heights = [Layout.Main.size.h, 116, 232]
            let old = column(top: CGPoint(x: 700, y: 955), skinHeights: heights, shaded: shaded, scale: s)
            let migrated = zip(old, [WindowLayout.mainSkinHeight(shaded: shaded), 116, 232]).map { f, h in
                WindowLayout.migratedTopLeft(legacyOrigin: f.origin, skinHeight: h, scale: s)
            }
            let first = launch(corners: migrated, skinHeights: heights, shaded: shaded, scale: s, backing: 2)
            c.equal("migration \(shaded ? "shaded" : "unshaded") \(s)x: no window jumps", first, old)
        }
    }

    /// The real key names and string format, through `Preferences`, in a throwaway defaults domain.
    /// A suite named by an absolute path is a plist at that path, so it lives in the selftest's
    /// temporary folder and goes with it; a named suite would leave a file in ~/Library/Preferences.
    private static func storedFormat(_ c: Checker, tmp: URL) {
        let suite = tmp.appendingPathComponent("window-prefs-\(UUID().uuidString).plist").path
        guard let defaults = UserDefaults(suiteName: suite) else {
            c.skip("stored window format", "could not open a scratch defaults domain")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)

        // What an earlier build left behind: bottom-left origins under the old keys, quit shaded.
        defaults.set("100.0,800.0", forKey: "mainOrigin")
        defaults.set("100.0,539.0", forKey: "plOrigin")
        defaults.set("100.0,191.0", forKey: "fieldOrigin")
        prefs.shadeMode = true
        prefs.playlistHeight = 174
        prefs.fieldHeight = 232
        c.check("old origins are seen as needing migration", prefs.hasLegacyOriginsToMigrate)
        c.equal("old key format parses", prefs.legacyOrigin(.main), CGPoint(x: 100, y: 800))

        prefs.migrateLegacyOrigins(scale: 1.5, shaded: prefs.shadeMode)
        c.equal("migrated main corner (strip, 21 pt)", prefs.topLeft(.main), CGPoint(x: 100, y: 821))
        c.equal("migrated Sessions corner (174 px -> 261 pt)", prefs.topLeft(.playlist), CGPoint(x: 100, y: 800))
        c.equal("migrated Token Flow corner (232 px -> 348 pt)", prefs.topLeft(.field), CGPoint(x: 100, y: 539))
        c.check("an equalizer that was never saved stays unstored", prefs.topLeft(.equalizer) == nil)
        c.check("nothing left to migrate", !prefs.hasLegacyOriginsToMigrate)
        c.equal("new corners live under their own key", defaults.string(forKey: "mainTopLeft"), "100.0,821.0")
        c.equal("old keys are left for older builds", defaults.string(forKey: "mainOrigin"), "100.0,800.0")

        // It runs once: an old origin written later (by an older build) does not overwrite a corner.
        defaults.set("5.0,5.0", forKey: "mainOrigin")
        prefs.migrateLegacyOrigins(scale: 1.5, shaded: true)
        c.equal("a second migration leaves corners alone", prefs.topLeft(.main), CGPoint(x: 100, y: 821))

        // Half-point corners (1.5x on Retina) survive the string round trip exactly.
        prefs.setTopLeft(CGPoint(x: 412.5, y: 1033.5), for: .equalizer)
        c.equal("fractional corner round trip", prefs.topLeft(.equalizer), CGPoint(x: 412.5, y: 1033.5))
    }

    // MARK: - Bug: every window opened off screen after a display was removed

    private static func offScreenRescue(_ c: Checker) {
        typealias Slot = WindowLayout.Slot
        // The built-in screen that is left, and the external one that was unplugged (x >= 1440).
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let external = CGRect(x: 1440, y: 0, width: 2560, height: 1415)
        let s = 1.5
        let lost = column(top: CGPoint(x: 2000, y: 1300), skinHeights: [116, 232, 232], shaded: false, scale: s)
        let (main, sessions, flow) = (lost[0], lost[1], lost[2])
        // Where a never-opened equalizer sits: its default slot, on the built-in screen.
        let eqDefault = CGRect(origin: CGPoint(x: 40, y: 40), size: main.size)
        let home = builtIn
        let target = CGPoint(x: home.minX + WindowLayout.rescueInset, y: home.maxY - WindowLayout.rescueInset)

        func apply(_ r: WindowLayout.Rescue, _ frames: [CGRect]) -> [CGRect] {
            frames.enumerated().map { i, f in
                r.moves.contains(i) ? f.offsetBy(dx: r.offset.dx, dy: r.offset.dy) : f
            }
        }

        // The reported case: equalizer closed (its default slot is on screen), Token Flow open.
        let reported = [Slot(frame: main, isOpen: true, isPlaced: true),
                        Slot(frame: eqDefault, isOpen: false, isPlaced: false),
                        Slot(frame: sessions, isOpen: true, isPlaced: true),
                        Slot(frame: flow, isOpen: true, isPlaced: true)]
        if let r = WindowLayout.rescue(reported, screens: [builtIn], home: home) {
            c.equal("unplugged, eq closed: main, Sessions and Token Flow move", r.moves, [0, 2, 3])
            let after = apply(r, reported.map { $0.frame })
            c.equal("unplugged: main's corner lands inside home", WindowLayout.topLeft(of: after[0]), target)
            c.check("unplugged: Sessions still docked to main", Docking.isAdjacent(after[0], after[2]))
            c.check("unplugged: Token Flow still docked to Sessions", Docking.isAdjacent(after[2], after[3]))
            c.check("unplugged: every open window is reachable",
                    [0, 2, 3].allSatisfy { WindowLayout.isReachable(after[$0], screens: [builtIn]) })
            c.equal("unplugged: the closed equalizer is not moved", after[1], eqDefault)
        } else {
            c.check("unplugged with the eq closed and Token Flow open is rescued", false)
        }
        c.check("same layout with the external display still attached: no move",
                WindowLayout.rescue(reported, screens: [builtIn, external], home: home) == nil)

        // Equalizer closed, but stored off screen too (it was docked beside main on the external).
        let eqBeside = CGRect(origin: CGPoint(x: main.maxX, y: main.minY), size: main.size)
        var withEq = reported
        withEq[1] = Slot(frame: eqBeside, isOpen: false, isPlaced: true)
        if let r = WindowLayout.rescue(withEq, screens: [builtIn], home: home) {
            c.equal("closed eq stored off screen travels with the group", r.moves, [0, 1, 2, 3])
            let after = apply(r, withEq.map { $0.frame })
            c.check("the equalizer keeps its place beside main", Docking.isAdjacent(after[0], after[1]))
        } else {
            c.check("a lost group with a lost closed equalizer is rescued", false)
        }
        // Closed equalizer stored on the built-in screen: it is not dragged off it.
        withEq[1] = Slot(frame: eqDefault, isOpen: false, isPlaced: true)
        c.equal("closed eq parked on a live screen stays put",
                WindowLayout.rescue(withEq, screens: [builtIn], home: home)?.moves, [0, 2, 3])
        // Open equalizer off screen with the rest: it votes and moves.
        withEq[1] = Slot(frame: eqBeside, isOpen: true, isPlaced: true)
        c.equal("open eq off screen moves with the group",
                WindowLayout.rescue(withEq, screens: [builtIn], home: home)?.moves, [0, 1, 2, 3])

        // Nothing off screen: no move.
        let onScreen = column(top: CGPoint(x: 40, y: 835), skinHeights: [116, 232, 232], shaded: false, scale: 1)
        let fine = [Slot(frame: onScreen[0], isOpen: true, isPlaced: true),
                    Slot(frame: eqDefault, isOpen: false, isPlaced: false),
                    Slot(frame: onScreen[1], isOpen: true, isPlaced: true),
                    Slot(frame: onScreen[2], isOpen: true, isPlaced: true)]
        c.check("nothing off screen: no move", WindowLayout.rescue(fine, screens: [builtIn], home: home) == nil)

        // Another open window still reachable no longer vetoes the rescue: the main window used to
        // stay on the unplugged display on every launch. It moves with what is docked to it and
        // nothing else; the lost Token Flow, docked to nothing that moves, goes to the foot of the
        // column, and the reachable Sessions stays where the user put it.
        var partly = reported
        partly[2] = Slot(frame: onScreen[1], isOpen: true, isPlaced: true)
        let partlyRescue = WindowLayout.rescue(partly, screens: [builtIn], home: home)
        c.equal("main lost, Sessions still reachable: the main window is rescued alone", partlyRescue?.moves, [0])
        c.equal("... and the lost Token Flow goes to the foot of the column", partlyRescue?.strays, [3])

        // Missing corners: a window with no stored corner sits in the default column on a live
        // screen; it must not veto the rescue, and it is not dragged along - it goes to the foot
        // of the column instead (SPEC 2.7).
        var missing = reported
        missing[3] = Slot(frame: onScreen[2], isOpen: true, isPlaced: false)
        c.equal("Token Flow never stored: main and Sessions still rescued",
                WindowLayout.rescue(missing, screens: [builtIn], home: home)?.moves, [0, 2])
        c.equal("Token Flow never stored: it goes to the foot of the column",
                WindowLayout.rescue(missing, screens: [builtIn], home: home)?.strays, [3])
        let mainOnly = [Slot(frame: main, isOpen: true, isPlaced: true),
                        Slot(frame: eqDefault, isOpen: false, isPlaced: false),
                        Slot(frame: onScreen[1], isOpen: true, isPlaced: false),
                        Slot(frame: onScreen[2], isOpen: true, isPlaced: false)]
        c.equal("only main stored: main alone is rescued",
                WindowLayout.rescue(mainOnly, screens: [builtIn], home: home)?.moves, [0])
        c.equal("only main stored: the open windows go to the foot of its column, in order",
                WindowLayout.rescue(mainOnly, screens: [builtIn], home: home)?.strays, [2, 3])
        let nothingStored = mainOnly.map { Slot(frame: $0.frame, isOpen: $0.isOpen, isPlaced: false) }
        c.check("nothing stored: nothing to rescue",
                WindowLayout.rescue(nothingStored, screens: [builtIn], home: home) == nil)

        // A shaded strip is rescued by its own corner.
        let strip = WindowLayout.resized(main, to: ScaleModel.contentSize(skin: Layout.Shade.size, points: s))
        var shaded = reported
        shaded[0] = Slot(frame: strip, isOpen: true, isPlaced: true)
        if let r = WindowLayout.rescue(shaded, screens: [builtIn], home: home) {
            c.equal("shaded strip lands at the home corner",
                    WindowLayout.topLeft(of: strip.offsetBy(dx: r.offset.dx, dy: r.offset.dy)), target)
        } else {
            c.check("a lost shaded strip is rescued", false)
        }

        // Opening a window later.
        c.check("never placed: opens at the foot of the column",
                WindowLayout.needsPlacementOnOpen(isPlaced: false, frame: eqDefault, screens: [builtIn]))
        c.check("placed on a live screen: opens where it was",
                !WindowLayout.needsPlacementOnOpen(isPlaced: true, frame: eqDefault, screens: [builtIn]))
        c.check("placed on a screen that is gone: opens at the foot of the column",
                WindowLayout.needsPlacementOnOpen(isPlaced: true, frame: eqBeside, screens: [builtIn]))
    }
}
