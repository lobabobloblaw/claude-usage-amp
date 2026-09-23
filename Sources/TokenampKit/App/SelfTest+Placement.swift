import CoreGraphics
import Foundation

/// Window placement on the screens there are (SPEC 2.7, 2.8): the main window's docked group kept
/// on screen after a scale change and at launch, the main window rescued even when the rest of the
/// layout is still reachable, windows with no place of their own put at the foot of the user's
/// column, Token Flow's height carrying what hangs under it (A7), and a relative `--skin` path
/// stored absolute. Pure geometry and strings; no window is created.
extension SelfTest {

    static func windowPlacement(_ c: Checker) {
        c.section("placement: the docked group kept on screen (SPEC 2.8)")
        groupOnScreen(c)
        groupOnScreenAtHalfPoints(c)
        c.section("placement: the main window rescued on its own, strays to the foot of the column (SPEC 2.7)")
        rescueMainAlone(c)
        c.section("placement: Token Flow's height carries what hangs under it (A7)")
        tokenFlowCarriesWhatHangsBelow(c)
        c.section("placement: a --skin path is remembered absolute (SPEC 2.6)")
        rememberedSkinPath(c)
    }

    /// The art rectangle of a window of `skin` pixels at `scale` whose top-left is `topLeft`.
    private static func placedArt(_ topLeft: CGPoint, _ skin: SkinPair, _ scale: Double) -> CGRect {
        let size = ScaleModel.contentSize(skin: skin, points: scale)
        let frame = CGRect(origin: WindowLayout.origin(topLeft: topLeft, height: size.height), size: size)
        return WindowLayout.skinRect(frame: frame, skinSize: skin, scale: scale)
    }

    /// A docked column as art rectangles, laid out the way the app lays it out (`Docking.column`).
    private static func columnArts(_ topLeft: CGPoint, _ scale: Double, _ sizes: [SkinPair]) -> [CGRect] {
        zip(Docking.column(topLeft: topLeft, scale: scale, skinSizes: sizes), sizes).map { placedArt($0, $1, scale) }
    }

    private static func shifted(_ rects: [CGRect], _ v: CGVector?) -> [CGRect] {
        rects.map { $0.offsetBy(dx: v?.dx ?? 0, dy: v?.dy ?? 0) }
    }

    // MARK: - Bug: a scale change left the stack running off the bottom of the screen

    private static func groupOnScreen(_ c: Checker) {
        // 1920x1200 Retina: a 25 pt menu bar, the Dock hidden. The default column starts 40 pt in.
        let visible = CGRect(x: 0, y: 0, width: 1_920, height: 1_175)
        let top = CGPoint(x: 40, y: 1_135)
        let sizes = [Layout.Main.size, Layout.Playlist.defaultSize, Layout.Field.defaultSize]

        // The reported case: 3x.
        let at3 = columnArts(top, 3, sizes)
        c.equal("3x: the main window's bottom is at 787 pt", at3[0].minY, 787)
        c.equal("3x: Sessions' is at 91 pt", at3[1].minY, 91)
        c.equal("3x: Token Flow's is at -605 pt, 87 % of it off screen", at3[2].minY, -605)
        let shift3 = WindowLayout.onScreenShift(at3, screens: [visible], home: visible)
        c.equal("3x: taller than the screen, so the stack moves up until its top is the screen's",
                shift3, CGVector(dx: 0, dy: 40))
        let moved3 = shifted(at3, shift3)
        c.equal("3x: the main window's top is the top of the visible frame", moved3[0].maxY, visible.maxY)
        c.check("3x: the stack is still docked",
                Docking.isAdjacent(moved3[0], moved3[1]) && Docking.isAdjacent(moved3[1], moved3[2]))
        c.check("3x: a second pass moves nothing",
                WindowLayout.onScreenShift(moved3, screens: [visible], home: visible) == nil)
        // Auto-fit then gives Sessions its minimum, the most of the stack there is room for (A7).
        let cap3 = PlaylistFit.maxHeight(art: moved3[1], below: [moved3[2]], screen: visible, scale: 3)
        c.equal("3x: then auto-fit has room for no more than Sessions' minimum",
                PlaylistFit.height(count: 8, rowHeight: 13, maxHeight: cap3), Layout.Playlist.minSize.h)

        // 2x: 1160 pt of stack fits in 1175, 25 pt too low - it moves up exactly that far.
        let at2 = columnArts(top, 2, sizes)
        let shift2 = WindowLayout.onScreenShift(at2, screens: [visible], home: visible)
        c.equal("2x: the stack moves up by the 25 pt it hangs off the bottom", shift2, CGVector(dx: 0, dy: 25))
        let moved2 = shifted(at2, shift2)
        c.equal("2x: its bottom lands on the screen's", moved2[2].minY, visible.minY)
        c.check("2x: and its top is still on screen", moved2[0].maxY <= visible.maxY)

        // Already on screen: nothing moves.
        c.check("1.5x: a stack already on screen does not move",
                WindowLayout.onScreenShift(columnArts(top, 1.5, sizes), screens: [visible], home: visible) == nil)
        // Half a point past the bottom is what whole-point rounding leaves a stack snapped to the
        // screen's bottom edge (A6); that is on screen.
        let snapped = [CGRect(x: 40, y: -0.5, width: 412.5, height: 391.5)]
        c.check("half a point past the edge is on screen",
                WindowLayout.onScreenShift(snapped, screens: [visible], home: visible) == nil)

        // Taller than the screen with its top above it: down until the top is on screen.
        let high = columnArts(CGPoint(x: 40, y: 1_300), 3, sizes)
        c.equal("too tall and too high: down until the top is the screen's",
                WindowLayout.onScreenShift(high, screens: [visible], home: visible), CGVector(dx: 0, dy: -125))

        // Sideways: the shortest move, left off the right edge, right off the left.
        let right = columnArts(CGPoint(x: 1_700, y: 1_160), 2, sizes)
        c.equal("off the right edge: left until its right edge is the screen's",
                WindowLayout.onScreenShift(right, screens: [visible], home: visible), CGVector(dx: -330, dy: 0))
        let left = columnArts(CGPoint(x: -100, y: 1_160), 2, sizes)
        c.equal("off the left edge: right until its left edge is the screen's",
                WindowLayout.onScreenShift(left, screens: [visible], home: visible), CGVector(dx: 100, dy: 0))
        // Wider than the screen: the left edge, where the title bars start, stays on it.
        let narrow = CGRect(x: 0, y: 0, width: 500, height: 1_175)
        let wide = columnArts(CGPoint(x: 100, y: 1_000), 2, sizes)
        c.equal("wider than the screen: the left edge goes to the screen's",
                WindowLayout.onScreenShift(wide, screens: [narrow], home: narrow)?.dx, -100)

        // Two displays side by side: a group spread over both, every window wholly on one or
        // across the seam, is on screen, although it is not inside the main window's display.
        let builtIn = CGRect(x: 0, y: 0, width: 1_440, height: 875)
        let external = CGRect(x: 1_440, y: 0, width: 2_560, height: 1_415)
        let mainArt = placedArt(CGPoint(x: 1_000, y: 800), Layout.Main.size, 2)
        let beside = placedArt(CGPoint(x: mainArt.maxX, y: mainArt.maxY), Layout.EQ.size, 2)
        let across = placedArt(CGPoint(x: 1_000, y: mainArt.minY), Layout.Playlist.defaultSize, 2)
        c.check("(the Sessions window straddles the seam)", across.minX < builtIn.maxX && across.maxX > external.minX)
        c.check("a group spread over two displays stays where the user put it",
                WindowLayout.onScreenShift([mainArt, beside, across], screens: [builtIn, external],
                                           home: builtIn) == nil)
        let offExternal = placedArt(CGPoint(x: beside.minX, y: beside.minY), Layout.Field.defaultSize, 2)
            .offsetBy(dx: 0, dy: -400)
        c.check("but one window off the bottom of either brings the group into the main window's screen",
                WindowLayout.onScreenShift([mainArt, beside, across, offExternal], screens: [builtIn, external],
                                           home: builtIn) != nil)
        c.check("no group, no move", WindowLayout.onScreenShift([], screens: [visible], home: visible) == nil)
    }

    /// The group moves by whole points, so at a half-point scale the windows keep the A6 rounding:
    /// each still touches the window above it or overlaps it by one device pixel, never gaps.
    /// Modelled the way the windows really move: a whole-point shift of each top-left corner,
    /// snapped to the device-pixel grid, with the art hung from it.
    private static func groupOnScreenAtHalfPoints(_ c: Checker) {
        let visible = CGRect(x: 0, y: 0, width: 1_920, height: 1_175)
        var whole = true, flush = true, inside = true, stable = true, topKept = true
        var cases = 0
        for scale in [1.5, 2.5, 3.0] {
            for sessionsHeight in [116, 145, 261, 290, 319] {
                let sizes = [Layout.Main.size, SkinPair(Layout.Playlist.defaultSize.w, sessionsHeight),
                             Layout.Field.defaultSize, Layout.EQ.size]
                for top in [CGPoint(x: 40, y: 1_135), CGPoint(x: 1_700, y: 700), CGPoint(x: -300, y: 2_000),
                            CGPoint(x: 900, y: 300), CGPoint(x: 41, y: 1_175)] {
                    let corners = Docking.column(topLeft: top, scale: scale, skinSizes: sizes)
                    let arts = zip(corners, sizes).map { placedArt($0, $1, scale) }
                    guard let shift = WindowLayout.onScreenShift(arts, screens: [visible], home: visible) else { continue }
                    cases += 1
                    if shift.dx != shift.dx.rounded() || shift.dy != shift.dy.rounded() { whole = false }
                    let moved = zip(corners, sizes).map { corner, skin -> CGRect in
                        let size = ScaleModel.contentSize(skin: skin, points: scale)
                        let origin = WindowLayout.origin(topLeft: CGPoint(x: corner.x + shift.dx, y: corner.y + shift.dy),
                                                         height: size.height)
                        let frame = CGRect(origin: SkinWindow.deviceAligned(origin, backing: 2), size: size)
                        return WindowLayout.skinRect(frame: frame, skinSize: skin, scale: scale)
                    }
                    for i in 1..<moved.count {
                        let overlap = moved[i].maxY - moved[i - 1].minY
                        if overlap < 0 || overlap > 0.5 { flush = false }
                    }
                    let union = moved.dropFirst().reduce(moved[0]) { $0.union($1) }
                    if union.height <= visible.height {
                        if !visible.contains(union) { inside = false }
                    } else if union.maxY > visible.maxY || union.maxY <= visible.maxY - 1 {
                        topKept = false
                    }
                    if WindowLayout.onScreenShift(moved, screens: [visible], home: visible) != nil { stable = false }
                }
            }
        }
        c.check("half-point scales: (the sweep moved some stacks)", cases >= 20)
        c.check("half-point scales: every shift is whole points", whole)
        c.check("half-point scales: docked windows touch or overlap by one device pixel, never gap", flush)
        c.check("half-point scales: a stack that fits ends up wholly inside the screen", inside)
        c.check("half-point scales: a stack taller than the screen has its top at the screen's", topKept)
        c.check("half-point scales: a second pass never moves anything", stable)
    }

    // MARK: - Bug: the main window stayed on an unplugged display while the rest was reachable

    private static func rescueMainAlone(_ c: Checker) {
        typealias Slot = WindowLayout.Slot
        let builtIn = CGRect(x: 0, y: 0, width: 1_440, height: 875)
        let target = CGPoint(x: builtIn.minX + WindowLayout.rescueInset, y: builtIn.maxY - WindowLayout.rescueInset)
        // Slots in the order the controller passes them: main, Sessions, Token Flow, equalizer.
        let lostMain = placedArt(CGPoint(x: 2_000, y: 1_300), Layout.Main.size, 1.5)
        let sessions = placedArt(CGPoint(x: 600, y: 800), Layout.Playlist.defaultSize, 1.5)
        let flow = placedArt(CGPoint(x: 600, y: sessions.minY), Layout.Field.defaultSize, 1.5)
        let eqBesideLostMain = placedArt(CGPoint(x: lostMain.maxX, y: lostMain.maxY), Layout.EQ.size, 1.5)
        let slots = [Slot(frame: lostMain, isOpen: true, isPlaced: true),
                     Slot(frame: sessions, isOpen: true, isPlaced: true),
                     Slot(frame: flow, isOpen: true, isPlaced: true),
                     Slot(frame: eqBesideLostMain, isOpen: false, isPlaced: true)]
        guard let r = WindowLayout.rescue(slots, screens: [builtIn], home: builtIn) else {
            c.check("main lost, Sessions and Token Flow reachable: the main window is rescued", false)
            return
        }
        c.equal("main lost, the rest reachable: main and the closed equalizer docked to it move", r.moves, [0, 3])
        c.equal("the main window lands at the home corner",
                WindowLayout.topLeft(of: lostMain.offsetBy(dx: r.offset.dx, dy: r.offset.dy)), target)
        c.check("the equalizer keeps its place beside it",
                Docking.isAdjacent(lostMain.offsetBy(dx: r.offset.dx, dy: r.offset.dy),
                                   eqBesideLostMain.offsetBy(dx: r.offset.dx, dy: r.offset.dy)))
        c.equal("Sessions and Token Flow stay where the user put them, and are no strays", r.strays, [])
        c.equal("the offset is whole points", r.offset, CGVector(dx: r.offset.dx.rounded(), dy: r.offset.dy.rounded()))

        // A lost window that is not docked to the main window is a stray, not a passenger.
        var parkedApart = slots
        parkedApart[2] = Slot(frame: placedArt(CGPoint(x: 3_000, y: 500), Layout.Field.defaultSize, 1.5),
                              isOpen: true, isPlaced: true)
        let apart = WindowLayout.rescue(parkedApart, screens: [builtIn], home: builtIn)
        c.equal("a lost Token Flow parked apart from the main window goes to the foot of the column",
                apart?.strays, [2])
        c.check("and does not travel with the main window", apart?.moves.contains(2) == false)

        // The main window on screen: nothing moves, but open windows without a place of their own
        // go to the foot of the column rather than the default column's slot (SPEC 2.7) - the
        // launch after an update that added a window.
        let mainHere = placedArt(CGPoint(x: 900, y: 870), Layout.Main.size, 1.5)
        let sessionsHere = placedArt(CGPoint(x: 900, y: mainHere.minY), Layout.Playlist.defaultSize, 1.5)
        let defaultSlot = placedArt(CGPoint(x: 40, y: 400), Layout.Field.defaultSize, 1.5)
        let upgraded = [Slot(frame: mainHere, isOpen: true, isPlaced: true),
                        Slot(frame: sessionsHere, isOpen: true, isPlaced: true),
                        Slot(frame: defaultSlot, isOpen: true, isPlaced: false),
                        Slot(frame: defaultSlot, isOpen: false, isPlaced: false)]
        let placed = WindowLayout.rescue(upgraded, screens: [builtIn], home: builtIn)
        c.equal("main on screen, Token Flow never placed: nothing moves", placed?.moves, [])
        c.equal("main on screen, Token Flow never placed: offset zero", placed?.offset, .zero)
        c.equal("main on screen, Token Flow never placed: it goes to the foot of the column", placed?.strays, [2])
        var allHome = upgraded
        allHome[2] = Slot(frame: placedArt(CGPoint(x: 900, y: sessionsHere.minY), Layout.Field.defaultSize, 1.5),
                          isOpen: true, isPlaced: true)
        c.check("everything placed and on screen, the closed equalizer never placed: nothing to do",
                WindowLayout.rescue(allHome, screens: [builtIn], home: builtIn) == nil)
    }

    // MARK: - Bug: resizing Token Flow left the windows docked under it behind

    private static func tokenFlowCarriesWhatHangsBelow(_ c: Checker) {
        let top = CGPoint(x: 100, y: 1_100)
        let sizes = [Layout.Main.size, Layout.Playlist.defaultSize, Layout.Field.defaultSize, Layout.EQ.size]
        let arts = columnArts(top, 1.5, sizes)
        let (mainArt, sessions, flow, eq) = (arts[0], arts[1], arts[2], arts[3])
        c.equal("under Token Flow, only the equalizer hanging from it follows its height",
                Docking.dockedBelow(flow, frames: [mainArt, sessions, eq]), [2])
        // Token Flow grows by one 29 px step at 1.5x: 43.5 pt, which the equalizer follows in whole
        // points, rounded towards Token Flow.
        let grown = placedArt(CGPoint(x: flow.minX, y: flow.maxY), SkinPair(Layout.Field.defaultSize.w,
                                                                           Layout.Field.defaultSize.h + 29), 1.5)
        let shift = Docking.followingShift(from: flow.minY, to: grown.minY)
        let eqAfter = eq.offsetBy(dx: 0, dy: shift)
        let overlap = eqAfter.maxY - grown.minY
        c.check("the equalizer moves by whole points", shift == shift.rounded())
        c.check("and still touches Token Flow or overlaps it by one device pixel", overlap >= 0 && overlap <= 0.5)
        // Token Flow at the top of a column: Sessions hanging under it follows it too.
        let flowTop = placedArt(top, Layout.Field.defaultSize, 1.5)
        let sessionsUnder = placedArt(CGPoint(x: top.x, y: flowTop.minY), Layout.Playlist.defaultSize, 1.5)
        c.equal("Sessions hanging under Token Flow follows it", Docking.dockedBelow(flowTop, frames: [sessionsUnder]), [0])
    }

    // MARK: - Bug: a relative --skin path was stored as typed, and a launch from Finder lost it

    private static func rememberedSkinPath(_ c: Checker) {
        let repo = "/Volumes/Work/tokenamp"
        let exists: (String) -> Bool = { _ in true }
        let missing: (String) -> Bool = { _ in false }
        c.equal("a relative path is stored absolute",
                Arguments.rememberedSkinSpec("skins/dist/Walnut76.wsz", currentDirectory: repo, fileExists: exists),
                "/Volumes/Work/tokenamp/skins/dist/Walnut76.wsz")
        c.equal("and standardized",
                Arguments.rememberedSkinSpec("./skins/../skins/dist/Walnut76.wsz", currentDirectory: repo,
                                             fileExists: exists),
                "/Volumes/Work/tokenamp/skins/dist/Walnut76.wsz")
        c.equal("a relative path from a subfolder",
                Arguments.rememberedSkinSpec("../dist/Bulkhead.wsz", currentDirectory: repo + "/skins/base",
                                             fileExists: exists),
                "/Volumes/Work/tokenamp/skins/dist/Bulkhead.wsz")
        c.equal("an absolute path is kept",
                Arguments.rememberedSkinSpec("/opt/skins/Classic.wsz", currentDirectory: repo, fileExists: exists),
                "/opt/skins/Classic.wsz")
        let home = Arguments.rememberedSkinSpec("~/Skins/Classic.wsz", currentDirectory: "/", fileExists: exists)
        c.check("a tilde is expanded", home.hasPrefix("/") && !home.contains("~") && home.hasSuffix("/Skins/Classic.wsz"))
        c.equal("the name of a bundled skin stays a name",
                Arguments.rememberedSkinSpec("Walnut76", currentDirectory: repo, fileExists: missing), "Walnut76")
        c.equal("the working directory is not asked about a name",
                Arguments.rememberedSkinSpec("Walnut76", currentDirectory: "/", fileExists: missing), "Walnut76")
    }
}
