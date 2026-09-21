import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UsageModel

/// Offscreen rendering (SPEC 3.1). No windows, no Screen Recording permission, no window server:
/// just the shared renderers drawing into bitmap contexts.
public enum SnapshotRunner {

    public struct Result {
        public var files: [URL]
        public var warnings: [String]
        public var skinName: String
    }

    /// Render `main.png`, `eq.png`, `playlist.png`, `shade.png` and `all.png` into `directory`.
    @discardableResult
    public static func run(directory: String, skin: Skin, snapshot: UsageSnapshot, scale: Int,
                           stateName: String?, now: Date) throws -> Result {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var state = makeState(snapshot: snapshot, scale: scale, now: now)
        if stateName?.lowercased() == "pressed" {
            // Exercise the alternate sprites: play held down, EQ toggle held, volume thumb grabbed.
            state.pressed = [.play, .eqToggle, .volume, .eqOn, .plScroll, .clutter("D")]
            state.latchedClutter = ["A"]
            state.playlistSelection = min(1, max(0, snapshot.sessionsToday.count - 1))
        }

        var files: [URL] = []

        let mainImage = try render(width: Layout.Main.size.w, height: Layout.Main.size.h, scale: scale) { c in
            MainRenderer.draw(c, skin: skin, snapshot: snapshot, state: state)
        }
        try write(mainImage, to: dir.appendingPathComponent("main.png"), &files)

        let eqImage = try render(width: Layout.EQ.size.w, height: Layout.EQ.size.h, scale: scale) { c in
            EQRenderer.draw(c, skin: skin, snapshot: snapshot, state: state)
        }
        try write(eqImage, to: dir.appendingPathComponent("eq.png"), &files)

        let plImage = try render(width: state.playlistWidth, height: state.playlistHeight, scale: scale) { c in
            PlaylistRenderer.draw(c, skin: skin, snapshot: snapshot, state: state)
        }
        try write(plImage, to: dir.appendingPathComponent("playlist.png"), &files)

        var shadeState = state
        shadeState.shadeMode = true
        let shadeImage = try render(width: Layout.Shade.size.w, height: Layout.Shade.size.h, scale: scale) { c in
            MainRenderer.drawShade(c, skin: skin, snapshot: snapshot, state: shadeState)
        }
        try write(shadeImage, to: dir.appendingPathComponent("shade.png"), &files)

        // all.png: the default stacked layout, main over EQ over playlist.
        let totalH = Layout.Main.size.h + Layout.EQ.size.h + state.playlistHeight
        let allImage = try render(width: Layout.Main.size.w, height: totalH, scale: scale) { c in
            MainRenderer.draw(c, skin: skin, snapshot: snapshot, state: state)
            c.save()
            c.ctx.translateBy(x: 0, y: CGFloat(Layout.Main.size.h))
            EQRenderer.draw(c, skin: skin, snapshot: snapshot, state: state)
            c.ctx.translateBy(x: 0, y: CGFloat(Layout.EQ.size.h))
            PlaylistRenderer.draw(c, skin: skin, snapshot: snapshot, state: state)
            c.restore()
        }
        try write(allImage, to: dir.appendingPathComponent("all.png"), &files)

        return Result(files: files, warnings: skin.warnings, skinName: skin.name)
    }

    /// The deterministic view state a snapshot renders: settled visualizer, marquee at the start.
    public static func makeState(snapshot: UsageSnapshot, scale: Int, now: Date) -> ViewState {
        var state = ViewState()
        state.now = now
        state.scale = Double(scale)
        state.heroIndex = 0
        state.playState = .playing
        state.timeMode = .remaining
        state.workLED = true
        state.shuffleOn = false
        state.repeatOn = true
        state.eqOpen = true
        state.plOpen = true
        state.mainIsKey = true
        state.eqIsKey = true
        state.playlistIsKey = true
        state.visualizerMode = .spectrum
        let settled = VisualizerModel.settled(snapshot, rows: Layout.Main.visualizer.h)
        state.visBars = settled.bars
        state.visPeaks = settled.peaks
        state.visScope = VisualizerModel.scope(snapshot)
        state.marqueeText = Marquee.compose(snapshot: snapshot, heroIndex: 0, isPaused: false,
                                            isStopped: false, now: now)
        state.marqueeOffset = 0
        state.playlistWidth = Layout.Playlist.defaultSize.w
        state.playlistHeight = Layout.Playlist.defaultSize.h
        state.playlistScroll = 0
        state.playlistShowsCost = true
        state.eqRange = .hours
        state.eqMeasure = .cost
        state.eqRelative = true
        return state
    }

    public enum SnapshotError: Swift.Error, CustomStringConvertible {
        case contextFailed
        case encodeFailed(String)
        public var description: String {
            switch self {
            case .contextFailed: return "could not create a bitmap context"
            case .encodeFailed(let p): return "could not write \(p)"
            }
        }
    }

    static func render(width: Int, height: Int, scale: Int, _ body: (SkinCanvas) -> Void) throws -> CGImage {
        guard let canvas = SkinCanvas.offscreen(width: width, height: height, scale: scale) else {
            throw SnapshotError.contextFailed
        }
        body(canvas)
        guard let image = canvas.makeImage() else { throw SnapshotError.contextFailed }
        return image
    }

    static func write(_ image: CGImage, to url: URL, _ files: inout [URL]) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SnapshotError.encodeFailed(url.path)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw SnapshotError.encodeFailed(url.path) }
        files.append(url)
    }
}
