import AppKit
import Foundation

/// Everything SPEC 2.6 says to persist, in `UserDefaults`, behind named accessors so no string
/// key is ever typed twice.
public final class Preferences {

    public static let shared = Preferences()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // NOTE: `scale` is deliberately NOT registered. SPEC 2.8 picks the first-run scale from the
        // screen, and a registered default would make `object(forKey:)` claim one was stored.
        defaults.register(defaults: [
            K.eqOpen: false,
            K.plOpen: true,
            K.alwaysOnTop: false,
            K.shuffle: false,
            K.repeatAlerts: false,
            K.shade: false,
            K.visualizerMode: VisualizerMode.spectrum.rawValue,
            K.eqRange: EQRange.hours.rawValue,
            K.eqMeasure: EQMeasure.cost.rawValue,
            K.eqRelative: true,
            K.eqAuto: false,
            K.pollInterval: 60.0,
            K.playlistShowsCost: true,
            K.playlistHeight: Layout.Playlist.defaultSize.h,
            K.fieldOpen: true,
            K.fieldMode: FieldMode.scope.rawValue,
            K.fieldAuto: true,
            K.fieldSpan: FieldSpan.minutes.rawValue,
            K.fieldWidth: Layout.Field.defaultSize.w,
            K.fieldHeight: Layout.Field.defaultSize.h,
            K.liveEnabled: true,
            K.demoData: false,
            K.menuBarReadout: false,
            K.heroIndex: 0,
            K.timeRemaining: true,
        ])
    }

    private enum K {
        static let skinPath = "skinPath"
        static let scale = "scale"
        static let mainOrigin = "mainOrigin"
        static let eqOrigin = "eqOrigin"
        static let plOrigin = "plOrigin"
        static let fieldOrigin = "fieldOrigin"
        static let fieldOpen = "fieldOpen"
        static let fieldMode = "fieldMode"
        static let fieldAuto = "fieldAuto"
        static let fieldSpan = "fieldSpan"
        static let fieldWidth = "fieldWidth"
        static let fieldHeight = "fieldHeight"
        static let eqOpen = "eqOpen"
        static let plOpen = "plOpen"
        static let shade = "shade"
        static let alwaysOnTop = "alwaysOnTop"
        static let shuffle = "shuffle"
        static let repeatAlerts = "repeatAlerts"
        static let visualizerMode = "visualizerMode"
        static let eqRange = "eqRange"
        static let eqMeasure = "eqMeasure"
        static let eqRelative = "eqRelative"
        static let eqAuto = "eqAuto"
        static let pollInterval = "pollInterval"
        static let playlistShowsCost = "playlistShowsCost"
        static let playlistHeight = "playlistHeight"
        static let liveEnabled = "liveEnabled"
        static let demoData = "demoData"
        static let menuBarReadout = "menuBarReadout"
        static let heroIndex = "heroIndex"
        static let timeRemaining = "timeRemaining"
    }

    // MARK: - Skin

    public var skinPath: String? {
        get { defaults.string(forKey: K.skinPath) }
        set { defaults.set(newValue, forKey: K.skinPath) }
    }

    /// Default when nothing is stored: the bundled skin named Base.
    public var effectiveSkinSpec: String { skinPath ?? SkinCatalog.defaultSkinName }

    // MARK: - Windows

    /// The user's chosen on-screen scale **in points per skin pixel** (SPEC 2.8, amendment A2).
    /// Half steps are meaningful on a Retina display; a whole number is stored on a 1x one.
    /// This is the preference, not necessarily what the current screen can honour - see
    /// `ScaleModel.nearest`.
    public var pointsScale: Double {
        get {
            let v = defaults.double(forKey: K.scale)
            guard v > 0 else { return 2 }
            return min(ScaleModel.maxPoints, max(ScaleModel.minPoints, v))
        }
        set { defaults.set(min(ScaleModel.maxPoints, max(ScaleModel.minPoints, newValue)), forKey: K.scale) }
    }

    /// False on a first run, when the scale is chosen from the screen instead.
    public var hasStoredScale: Bool { defaults.object(forKey: K.scale) != nil }

    /// The Usage Equalizer starts closed: its sliders are read-only gauges, so it is the one
    /// window that has to be asked for (SPEC 2.6).
    public var eqOpen: Bool {
        get { defaults.bool(forKey: K.eqOpen) }
        set { defaults.set(newValue, forKey: K.eqOpen) }
    }

    public var playlistOpen: Bool {
        get { defaults.bool(forKey: K.plOpen) }
        set { defaults.set(newValue, forKey: K.plOpen) }
    }

    /// Token Flow opens with the app: a window nobody knows about is a window nobody opens
    /// (SPEC 2.9). It sits beside the stack rather than extending it, so the default layout is no
    /// taller than it was.
    public var fieldOpen: Bool {
        get { defaults.bool(forKey: K.fieldOpen) }
        set { defaults.set(newValue, forKey: K.fieldOpen) }
    }

    public var fieldMode: FieldMode {
        get { FieldMode(rawValue: defaults.string(forKey: K.fieldMode) ?? "") ?? .scope }
        set { defaults.set(newValue.rawValue, forKey: K.fieldMode) }
    }

    public var fieldAuto: Bool {
        get { defaults.bool(forKey: K.fieldAuto) }
        set { defaults.set(newValue, forKey: K.fieldAuto) }
    }

    public var fieldSpan: FieldSpan {
        get { FieldSpan(rawValue: defaults.string(forKey: K.fieldSpan) ?? "") ?? .minutes }
        set { defaults.set(newValue.rawValue, forKey: K.fieldSpan) }
    }

    public var fieldWidth: Int {
        get { max(Layout.Field.minSize.w, defaults.integer(forKey: K.fieldWidth)) }
        set { defaults.set(newValue, forKey: K.fieldWidth) }
    }

    public var fieldHeight: Int {
        get { max(Layout.Field.minSize.h, defaults.integer(forKey: K.fieldHeight)) }
        set { defaults.set(newValue, forKey: K.fieldHeight) }
    }

    public var shadeMode: Bool {
        get { defaults.bool(forKey: K.shade) }
        set { defaults.set(newValue, forKey: K.shade) }
    }

    public var alwaysOnTop: Bool {
        get { defaults.bool(forKey: K.alwaysOnTop) }
        set { defaults.set(newValue, forKey: K.alwaysOnTop) }
    }

    public var playlistHeight: Int {
        get { max(Layout.Playlist.minSize.h, defaults.integer(forKey: K.playlistHeight)) }
        set { defaults.set(newValue, forKey: K.playlistHeight) }
    }

    public func origin(_ which: WindowKey) -> CGPoint? {
        guard let s = defaults.string(forKey: which.key) else { return nil }
        let parts = s.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }

    public func setOrigin(_ p: CGPoint, for which: WindowKey) {
        defaults.set("\(p.x),\(p.y)", forKey: which.key)
    }

    public enum WindowKey {
        case main, equalizer, playlist, field
        var key: String {
            switch self {
            case .main: return K.mainOrigin
            case .equalizer: return K.eqOrigin
            case .playlist: return K.plOrigin
            case .field: return K.fieldOrigin
            }
        }
    }

    // MARK: - Toggles

    public var shuffle: Bool {
        get { defaults.bool(forKey: K.shuffle) }
        set { defaults.set(newValue, forKey: K.shuffle) }
    }

    public var repeatAlerts: Bool {
        get { defaults.bool(forKey: K.repeatAlerts) }
        set { defaults.set(newValue, forKey: K.repeatAlerts) }
    }

    public var visualizerMode: VisualizerMode {
        get { VisualizerMode(rawValue: defaults.string(forKey: K.visualizerMode) ?? "") ?? .spectrum }
        set { defaults.set(newValue.rawValue, forKey: K.visualizerMode) }
    }

    public var eqRange: EQRange {
        get { EQRange(rawValue: defaults.string(forKey: K.eqRange) ?? "") ?? .hours }
        set { defaults.set(newValue.rawValue, forKey: K.eqRange) }
    }

    public var eqMeasure: EQMeasure {
        get { EQMeasure(rawValue: defaults.string(forKey: K.eqMeasure) ?? "") ?? .cost }
        set { defaults.set(newValue.rawValue, forKey: K.eqMeasure) }
    }

    public var eqRelative: Bool {
        get { defaults.bool(forKey: K.eqRelative) }
        set { defaults.set(newValue, forKey: K.eqRelative) }
    }

    public var eqAuto: Bool {
        get { defaults.bool(forKey: K.eqAuto) }
        set { defaults.set(newValue, forKey: K.eqAuto) }
    }

    public var pollInterval: TimeInterval {
        get { max(30, min(900, defaults.double(forKey: K.pollInterval))) }
        set { defaults.set(max(30, min(900, newValue)), forKey: K.pollInterval) }
    }

    public var playlistShowsCost: Bool {
        get { defaults.bool(forKey: K.playlistShowsCost) }
        set { defaults.set(newValue, forKey: K.playlistShowsCost) }
    }

    public var liveEnabled: Bool {
        get { defaults.bool(forKey: K.liveEnabled) }
        set { defaults.set(newValue, forKey: K.liveEnabled) }
    }

    public var demoData: Bool {
        get { defaults.bool(forKey: K.demoData) }
        set { defaults.set(newValue, forKey: K.demoData) }
    }

    public var menuBarReadout: Bool {
        get { defaults.bool(forKey: K.menuBarReadout) }
        set { defaults.set(newValue, forKey: K.menuBarReadout) }
    }

    public var heroIndex: Int {
        get { defaults.integer(forKey: K.heroIndex) }
        set { defaults.set(newValue, forKey: K.heroIndex) }
    }

    public var timeRemaining: Bool {
        get { defaults.bool(forKey: K.timeRemaining) }
        set { defaults.set(newValue, forKey: K.timeRemaining) }
    }
}
