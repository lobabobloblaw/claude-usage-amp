import CoreGraphics
import Foundation
import UsageModel

/// Identifies one interactive element. A struct rather than an enum so indexed controls
/// (EQ bands, playlist rows) can be addressed without a parallel type.
public struct ControlID: Hashable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public var description: String { raw }

    // Main window
    public static let titleBar = ControlID("titleBar")
    /// The chassis behind everything: drags the window, but is not the title bar.
    public static let background = ControlID("background")
    public static let optionsButton = ControlID("optionsButton")
    public static let minimizeButton = ControlID("minimizeButton")
    public static let shadeButton = ControlID("shadeButton")
    public static let closeButton = ControlID("closeButton")
    public static let previous = ControlID("previous")
    public static let play = ControlID("play")
    public static let pause = ControlID("pause")
    public static let stop = ControlID("stop")
    public static let next = ControlID("next")
    public static let eject = ControlID("eject")
    public static let shuffle = ControlID("shuffle")
    public static let repeatToggle = ControlID("repeat")
    public static let eqToggle = ControlID("eqToggle")
    public static let plToggle = ControlID("plToggle")
    public static let volume = ControlID("volume")
    public static let balance = ControlID("balance")
    public static let posbar = ControlID("posbar")
    public static let marquee = ControlID("marquee")
    public static let timeDisplay = ControlID("timeDisplay")
    public static let visualizer = ControlID("visualizer")
    public static let kbps = ControlID("kbps")
    public static let khz = ControlID("khz")
    public static let monoster = ControlID("monoster")
    public static let aboutLogo = ControlID("aboutLogo")
    public static func clutter(_ letter: String) -> ControlID { ControlID("clutter:" + letter) }

    // Equalizer
    public static let eqTitleBar = ControlID("eqTitleBar")
    public static let eqClose = ControlID("eqClose")
    public static let eqOn = ControlID("eqOn")
    public static let eqAuto = ControlID("eqAuto")
    public static let eqPresets = ControlID("eqPresets")
    public static let eqPreamp = ControlID("eqPreamp")
    public static let eqGraph = ControlID("eqGraph")
    public static func eqBand(_ i: Int) -> ControlID { ControlID("eqBand:\(i)") }
    public var eqBandIndex: Int? {
        guard raw.hasPrefix("eqBand:") else { return nil }
        return Int(raw.dropFirst("eqBand:".count))
    }

    // Playlist
    public static let plTitleBar = ControlID("plTitleBar")
    public static let plClose = ControlID("plClose")
    public static let plList = ControlID("plList")
    public static let plScroll = ControlID("plScroll")
    public static let plResize = ControlID("plResize")
}

/// A declarative hit region: a rect in skin pixels plus what it does when clicked.
public struct HitRegion {
    public let id: ControlID
    public let rect: SpriteRect
    /// Redraw while the mouse is held down inside it (buttons with a pressed sprite).
    public let showsPressed: Bool
    /// Replace the marquee with this control's reading while hovered (SPEC 2.5).
    public let hasHoverReading: Bool
    /// Dragging here moves the window.
    public let dragsWindow: Bool

    public init(_ id: ControlID, _ rect: SpriteRect, showsPressed: Bool = true,
                hasHoverReading: Bool = false, dragsWindow: Bool = false) {
        self.id = id
        self.rect = rect
        self.showsPressed = showsPressed
        self.hasHoverReading = hasHoverReading
        self.dragsWindow = dragsWindow
    }
}

public enum PlayState: String, Codable {
    case playing
    case paused
    case stopped
}

/// Everything the renderers need beyond the skin and the snapshot. A plain value type, so the
/// live views and the offscreen snapshot renderer can be handed identical input.
public struct ViewState {
    public var now: Date = Date()
    /// Points per skin pixel on screen; PNG pixels per skin pixel for `--snapshot` (SPEC 2.8).
    public var scale: Double = 2

    // transport / tracklist
    public var heroIndex: Int = 0
    public var playState: PlayState = .playing
    public var timeMode: TimeFormatting.DigitMode = .remaining
    public var workLED: Bool = false
    public var shuffleOn: Bool = false
    public var repeatOn: Bool = false
    public var eqOpen: Bool = true
    public var plOpen: Bool = true
    public var alwaysOnTop: Bool = false
    public var shadeMode: Bool = false

    // visualizer
    public var visualizerMode: VisualizerMode = .spectrum
    public var visBars: [Double] = []
    public var visPeaks: [Double] = []
    public var visScope: [Double] = []

    // marquee
    public var marqueeText: String = ""
    public var marqueeOffset: Int = 0

    /// The skin-pixel rect the window is being asked to repaint, or nil for "everything".
    /// Renderers use it to skip whole sections during the 30 fps animation frames.
    public var dirtyRect: SpriteRect? = nil

    // interaction
    public var pressed: Set<ControlID> = []
    public var hover: ControlID? = nil
    public var mainIsKey: Bool = true
    public var eqIsKey: Bool = false
    public var playlistIsKey: Bool = false
    /// Clutter letters that are latched on (A = always on top, V while the menu is open...).
    public var latchedClutter: Set<String> = []

    // equalizer
    public var eqRange: EQRange = .hours
    public var eqMeasure: EQMeasure = .cost
    public var eqRelative: Bool = true
    public var eqAuto: Bool = false

    // playlist
    public var playlistWidth: Int = Layout.Playlist.defaultSize.w
    public var playlistHeight: Int = Layout.Playlist.defaultSize.h
    public var playlistScroll: Int = 0
    public var playlistSelection: Int? = nil
    public var playlistShowsCost: Bool = true

    public init() {}

    public func isPressed(_ id: ControlID) -> Bool { pressed.contains(id) }

    public var isStopped: Bool { playState == .stopped }
    public var isPaused: Bool { playState == .paused }
}
