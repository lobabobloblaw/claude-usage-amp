import AppKit
import Foundation
import UniformTypeIdentifiers
import UsageModel

/// The hub: owns the provider, the skin, the three windows, the animation clock and every piece
/// of UI state that is not a pure function of the snapshot.
public final class TokenampController: NSObject {

    // MARK: - Collaborators

    public private(set) var provider: UsageProvider
    public private(set) var snapshot: UsageSnapshot
    public private(set) var skin: Skin
    public let prefs: Preferences
    public let docking = DockingManager()

    public private(set) var mainWindow: MainWindowController!
    public private(set) var equalizer: EqualizerWindowController!
    public private(set) var playlist: PlaylistWindowController!
    private var statusItem: StatusItemController?
    private let notifier = ThresholdNotifier()

    /// Rebuilt whenever the user picks a different provider mode.
    private let providerFactory: (Bool) -> UsageProvider
    /// False while the executable still hands back demo data for a "live" run.
    public let liveProviderAvailable: Bool
    /// Extra lines for the clutterbar "I" panel (SPEC 2.1 asks it for data sources and paths).
    /// TokenampKit cannot see UsageCore, so the executable - the one target that sees both - passes
    /// a formatter in, and it is called with whichever provider is in use at the time.
    public var providerDiagnostics: ((UsageProvider) -> [String])?
    /// `--demo` on the command line: a session override, deliberately NOT written to the
    /// preference, so one debugging run does not silently keep showing synthetic numbers.
    private var demoOverride: Bool

    /// What the provider is actually running on right now.
    public var isUsingDemoData: Bool { demoOverride || prefs.demoData }

    // MARK: - UI state

    public private(set) var heroIndex: Int
    public private(set) var playState: PlayState = .playing
    public private(set) var visualizerMode: VisualizerMode
    private let visualizer = VisualizerModel()

    private var marqueeText = ""
    private var marqueeOffset = 0.0
    private var marqueeScrubAnchor = 0.0
    private var hoverReading: String?
    private var hoverExpiry: Date?
    private var lastDataAt: Date?
    private var lastEventSignature: String = ""
    private var lastShuffleAt = Date()
    private var lastEQRotateAt = Date()
    private var lastDigits = ""
    private var lastEQSignature = ""
    private var lastPlaylistSignature = ""

    private var timer: Timer?
    private var lastTick = Date()
    private var animating = true
    public private(set) var skinLoadError: String?

    // MARK: - Scale (SPEC 2.8, amendment A2)

    /// Points per skin pixel actually in use: the stored preference (or the screen-derived default
    /// on a first run), snapped to what the main window's current screen can render as whole
    /// device pixels.
    public private(set) var scale: Double = 2

    /// Backing factor of the screen the main window is on.
    public var backingFactor: CGFloat {
        mainWindow?.window.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 1
    }

    /// Whole device pixels per skin pixel right now - the number SPEC 2.8 actually cares about.
    public var pixelsPerSkinPixel: Int { ScaleModel.ppsp(points: scale, backing: backingFactor) }

    // MARK: - Init

    public init(providerFactory: @escaping (Bool) -> UsageProvider,
                liveProviderAvailable: Bool,
                prefs: Preferences = .shared,
                forceDemo: Bool = false,
                skinOverride: String? = nil) {
        self.providerFactory = providerFactory
        self.liveProviderAvailable = liveProviderAvailable
        self.prefs = prefs
        demoOverride = forceDemo
        let p = providerFactory(forceDemo || prefs.demoData)
        provider = p
        snapshot = p.snapshot
        let loaded = SkinCatalog.load(skinOverride ?? prefs.effectiveSkinSpec)
        skin = loaded.skin
        skinLoadError = loaded.error
        heroIndex = prefs.heroIndex
        visualizerMode = prefs.visualizerMode
        super.init()
        if let skinOverride { prefs.skinPath = skinOverride }
    }

    // MARK: - Lifecycle

    public func start() {
        scale = resolvedStartScale()
        mainWindow = MainWindowController(app: self)
        equalizer = EqualizerWindowController(app: self)
        playlist = PlaylistWindowController(app: self)

        docking.main = mainWindow.window
        docking.equalizer = equalizer.window
        docking.playlist = playlist.window
        docking.scale = scale

        restoreWindowPositions()
        // The stored origin may put the main window on a screen with a different backing factor
        // than the one we guessed from; honour that screen without touching the preference.
        reconcileScaleWithCurrentScreen()
        applyAlwaysOnTop()

        mainWindow.window.makeKeyAndOrderFront(nil)
        if prefs.shadeMode { mainWindow.setShade(true, persist: false) }
        if prefs.eqOpen { equalizer.show() }
        if prefs.playlistOpen { playlist.show() }
        if prefs.menuBarReadout { setMenuBarReadout(true) }

        provider.onChange = { [weak self] snap in self?.ingest(snap) }
        provider.isLiveEnabled = prefs.liveEnabled
        provider.livePollInterval = prefs.pollInterval
        provider.start()
        ingest(provider.snapshot)
        visualizer.settle(snapshot: snapshot)

        // Persist the layout we ended up with, so it survives even an abrupt exit.
        saveWindowPositions()

        lastTick = Date()
        scheduleTimer(fast: true)
    }

    public func stopAndSave() {
        timer?.invalidate()
        timer = nil
        provider.stop()
        saveWindowPositions()
    }

    // MARK: - Snapshot flow

    private func ingest(_ snap: UsageSnapshot) {
        let signature = "\(snap.lastEventAt?.timeIntervalSince1970 ?? 0)|\(snap.today.tokens.total)|\(snap.limits.map { $0.percent })"
        if signature != lastEventSignature {
            lastEventSignature = signature
            lastDataAt = Date()
        }
        snapshot = snap
        heroIndex = HeroTrack.resolveIndex(heroIndex, count: max(1, snap.limits.count))
        rebuildMarquee()
        if prefs.repeatAlerts { notifier.check(snapshot: snap) }
        statusItem?.update(snapshot: snap, now: Date())
        // The EQ and the playlist only change when their data does, which is far less often than
        // the 30 fps main window; redrawing them on every publish is pure waste.
        let eqSig = "\(snap.hours.last?.costUSD ?? 0)|\(snap.days.last?.costUSD ?? 0)|"
            + "\(snap.minutes.last?.costUSD ?? 0)|\(snap.limits.map { $0.percent })"
        if eqSig != lastEQSignature {
            lastEQSignature = eqSig
            equalizer.view.needsDisplay = true
        }
        let plSig = "\(snap.sessionsToday.count)|\(snap.sessionsToday.map { $0.costUSD })|\(snap.today.costUSD)"
        if plSig != lastPlaylistSignature {
            lastPlaylistSignature = plSig
            playlist.view.needsDisplay = true
        }
        setAnimating(true)
    }

    private func rebuildMarquee() {
        let text = Marquee.compose(snapshot: snapshot, heroIndex: heroIndex,
                                   isPaused: playState == .paused, isStopped: playState == .stopped,
                                   now: Date())
        if text != marqueeText {
            marqueeText = text
            if marqueeOffset > Double(Marquee.scrollWidth(text)) { marqueeOffset = 0 }
        }
    }

    // MARK: - Animation

    private func scheduleTimer(fast: Bool) {
        timer?.invalidate()
        let interval = fast ? 1.0 / 30.0 : 1.0 / 4.0
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval * 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
        animating = fast
    }

    private func setAnimating(_ on: Bool) {
        guard on != animating else { return }
        scheduleTimer(fast: on)
    }

    private func tick() {
        let now = Date()
        let dt = max(0.001, min(0.25, now.timeIntervalSince(lastTick)))
        lastTick = now

        // Hero auto-cycle (Shuffle).
        if prefs.shuffle, playState == .playing, now.timeIntervalSince(lastShuffleAt) >= 8 {
            lastShuffleAt = now
            selectHero(HeroTrack.next(heroIndex, count: max(1, snapshot.limits.count)))
        }
        // EQ auto range rotation.
        if prefs.eqAuto, now.timeIntervalSince(lastEQRotateAt) >= 10 {
            lastEQRotateAt = now
            prefs.eqRange = prefs.eqRange.next
            equalizer.view.needsDisplay = true
        }

        // Visualizer.
        var visMoved = false
        if visualizerMode != .off {
            visualizer.gain = playState == .stopped ? 0 : 1
            let before = visualizer.bars
            visualizer.advance(snapshot: snapshot, now: now, dt: dt, rows: Layout.Main.visualizer.h)
            visMoved = zip(before, visualizer.bars).contains { abs($0 - $1) > 0.002 }
        }

        // Marquee: 1 px per 40 ms (SPEC 3, "pick what looks right and keep it smooth").
        var marqueeMoved = false
        if hoverReading == nil, playState != .stopped, !marqueeText.isEmpty {
            marqueeOffset += dt / 0.04
            let width = Double(Marquee.scrollWidth(marqueeText))
            if marqueeOffset >= width { marqueeOffset -= width }
            marqueeMoved = true
        }

        // Hover linger.
        if let expiry = hoverExpiry, now >= expiry {
            hoverExpiry = nil
            hoverReading = nil
            marqueeMoved = true
        }

        // Digits tick once per second; recompose the marquee with them.
        let readout = TimeFormatting.readout(hero: currentHero, mode: timeMode, now: now)
        let digitsChanged = readout.glyphs != lastDigits
        if digitsChanged {
            lastDigits = readout.glyphs
            rebuildMarquee()
            statusItem?.update(snapshot: snapshot, now: now)
            if let pl = playlist, pl.window.isVisible { pl.refreshMiniTime() }
        }

        mainWindow.animate(visualizerMoved: visMoved, marqueeMoved: marqueeMoved,
                           digitsChanged: digitsChanged, workLED: workLEDIsOn(now))

        // Idle down when nothing is moving, so a parked app costs ~nothing.
        let busy = visMoved || marqueeMoved || playState == .playing
        setAnimating(busy)
    }

    private func workLEDIsOn(_ now: Date) -> Bool {
        guard playState != .stopped, let at = lastDataAt else { return false }
        return now.timeIntervalSince(at) < 0.6
    }

    // MARK: - Derived state

    public var currentHero: LimitGauge? { HeroTrack.hero(in: snapshot, index: heroIndex) }

    public var timeMode: TimeFormatting.DigitMode { prefs.timeRemaining ? .remaining : .elapsed }

    /// The view state handed to every renderer this frame.
    public func viewState() -> ViewState {
        var s = ViewState()
        let now = Date()
        s.now = now
        s.scale = scale
        s.heroIndex = heroIndex
        s.playState = playState
        s.timeMode = timeMode
        s.workLED = workLEDIsOn(now)
        s.shuffleOn = prefs.shuffle
        s.repeatOn = prefs.repeatAlerts
        s.eqOpen = equalizer?.window.isVisible ?? prefs.eqOpen
        s.plOpen = playlist?.window.isVisible ?? prefs.playlistOpen
        s.alwaysOnTop = prefs.alwaysOnTop
        s.shadeMode = mainWindow?.isShade ?? false
        s.visualizerMode = visualizerMode
        s.visBars = visualizer.bars
        s.visPeaks = visualizer.peaks
        // Only the oscilloscope needs the 76-sample trace; do not build it 30 times a second
        // for a spectrum that will not read it.
        s.visScope = visualizerMode == .oscilloscope ? VisualizerModel.scope(snapshot) : []
        s.marqueeText = hoverReading.map { BitmapFont.sanitize($0) } ?? marqueeText
        s.marqueeOffset = hoverReading == nil ? Int(marqueeOffset) : 0
        s.mainIsKey = mainWindow?.window.isKeyWindow ?? false
        s.eqIsKey = equalizer?.window.isKeyWindow ?? false
        s.playlistIsKey = playlist?.window.isKeyWindow ?? false
        s.latchedClutter = prefs.alwaysOnTop ? ["A"] : []
        s.eqRange = prefs.eqRange
        s.eqMeasure = prefs.eqMeasure
        s.eqRelative = prefs.eqRelative
        s.eqAuto = prefs.eqAuto
        s.playlistWidth = Layout.Playlist.defaultSize.w
        s.playlistHeight = prefs.playlistHeight
        s.playlistScroll = playlist?.scroll ?? 0
        s.playlistSelection = playlist?.selection
        s.playlistShowsCost = prefs.playlistShowsCost
        return s
    }

    // MARK: - Actions

    public func selectHero(_ index: Int) {
        heroIndex = HeroTrack.resolveIndex(index, count: max(1, snapshot.limits.count))
        prefs.heroIndex = heroIndex
        rebuildMarquee()
        marqueeOffset = 0
        mainWindow.view.needsDisplay = true
        equalizer.view.needsDisplay = true
    }

    public func setPlayState(_ s: PlayState) {
        playState = s
        provider.isPaused = (s != .playing)
        if s == .stopped { visualizer.silence() }
        rebuildMarquee()
        mainWindow.view.needsDisplay = true
        setAnimating(true)
    }

    public func resumeAndRefresh() {
        setPlayState(.playing)
        provider.refreshNow()
        lastDataAt = Date()
    }

    public func togglePause() {
        setPlayState(playState == .paused ? .playing : .paused)
    }

    public func toggleTimeMode() {
        prefs.timeRemaining.toggle()
        mainWindow.view.needsDisplay = true
    }

    public func cycleVisualizer() {
        visualizerMode = visualizerMode.next
        prefs.visualizerMode = visualizerMode
        mainWindow.view.needsDisplay = true
    }

    public func setVisualizerMode(_ m: VisualizerMode) {
        visualizerMode = m
        prefs.visualizerMode = m
        mainWindow.view.needsDisplay = true
    }

    public func toggleShuffle() {
        prefs.shuffle.toggle()
        lastShuffleAt = Date()
        mainWindow.view.needsDisplay = true
    }

    public func toggleRepeatAlerts() {
        prefs.repeatAlerts.toggle()
        if prefs.repeatAlerts {
            notifier.prime(snapshot: snapshot)
            notifier.requestAuthorizationIfPossible()
        }
        mainWindow.view.needsDisplay = true
    }

    public func toggleEqualizer() {
        if equalizer.window.isVisible { equalizer.hide() } else { equalizer.show() }
        prefs.eqOpen = equalizer.window.isVisible
        mainWindow.view.needsDisplay = true
    }

    public func togglePlaylist() {
        if playlist.window.isVisible { playlist.hide() } else { playlist.show() }
        prefs.playlistOpen = playlist.window.isVisible
        mainWindow.view.needsDisplay = true
    }

    public func toggleAlwaysOnTop() {
        prefs.alwaysOnTop.toggle()
        applyAlwaysOnTop()
        mainWindow.view.needsDisplay = true
    }

    private func applyAlwaysOnTop() {
        let level: NSWindow.Level = prefs.alwaysOnTop ? .floating : .normal
        mainWindow?.window.level = level
        equalizer?.window.level = level
        playlist?.window.level = level
    }

    /// The screen the main window will land on before it exists: the one holding the stored
    /// origin, else the main screen.
    private func startupScreen() -> NSScreen? {
        if let origin = prefs.origin(.main) {
            if let s = NSScreen.screens.first(where: { $0.frame.contains(origin) }) { return s }
        }
        return NSScreen.main
    }

    private func resolvedStartScale() -> Double {
        let screen = startupScreen()
        let backing = screen?.backingScaleFactor ?? 1
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let wanted = prefs.hasStoredScale
            ? prefs.pointsScale
            : ScaleModel.defaultPointScale(visibleFrame: visible, backing: backing)
        return ScaleModel.nearest(wanted, backing: backing)
    }

    /// SPEC 2.8: when the main window is on a screen whose backing factor makes the stored scale
    /// invalid (1.5x on a 1x display), use the nearest valid scale *there* without overwriting the
    /// preference.
    public func reconcileScaleWithCurrentScreen() {
        guard mainWindow != nil else { return }
        let wanted = prefs.hasStoredScale ? prefs.pointsScale : scale
        let resolved = ScaleModel.nearest(wanted, backing: backingFactor)
        guard abs(resolved - scale) > 1e-9 else { return }
        applyScale(resolved)
    }

    /// Clutterbar **D** and the Scale menu: step to the next scale valid on this screen.
    public func cycleScale() {
        setScale(ScaleModel.next(after: scale, backing: backingFactor))
    }

    /// A scale the user picked: persisted, unlike a screen-forced one.
    public func setScale(_ points: Double) {
        let resolved = ScaleModel.nearest(points, backing: backingFactor)
        prefs.pointsScale = resolved
        guard abs(resolved - scale) > 1e-9 else { return }
        applyScale(resolved)
    }

    /// Resize every window around the main window's fixed top-left and put the docked ones back
    /// where they belong (SPEC 2.8). Windows the user parked elsewhere are left alone.
    private func applyScale(_ points: Double) {
        let before = docking.captureLayout()
        scale = points
        docking.scale = points
        mainWindow.applyScale(points)
        equalizer.applyScale(points)
        playlist.applyScale(points)
        docking.relayoutDocked(from: before)
        clampOnScreen()
        saveWindowPositions()
    }

    public func toggleShade() { mainWindow.setShade(!mainWindow.isShade, persist: true) }

    public func setLiveEnabled(_ on: Bool) {
        prefs.liveEnabled = on
        provider.isLiveEnabled = on
        provider.refreshNow()
    }

    public func setPollInterval(_ seconds: TimeInterval) {
        prefs.pollInterval = seconds
        provider.livePollInterval = prefs.pollInterval
    }

    public func setPlaylistShowsCost(_ cost: Bool) {
        prefs.playlistShowsCost = cost
        playlist.view.needsDisplay = true
    }

    public func setDemoData(_ on: Bool) {
        guard on != isUsingDemoData else { return }
        prefs.demoData = on
        demoOverride = false
        provider.stop()
        provider.onChange = nil
        let p = providerFactory(on)
        provider = p
        p.isLiveEnabled = prefs.liveEnabled
        p.livePollInterval = prefs.pollInterval
        p.isPaused = playState != .playing
        p.onChange = { [weak self] snap in self?.ingest(snap) }
        p.start()
        ingest(p.snapshot)
    }

    public func refreshNow() {
        provider.refreshNow()
        lastDataAt = Date()
    }

    public func setMenuBarReadout(_ on: Bool) {
        prefs.menuBarReadout = on
        if on {
            if statusItem == nil { statusItem = StatusItemController(app: self) }
            statusItem?.update(snapshot: snapshot, now: Date())
        } else {
            statusItem?.remove()
            statusItem = nil
        }
    }

    // MARK: - Hover readings (SPEC 2.5)

    public func setHover(_ id: ControlID?) {
        guard let id else {
            // 1.5 s linger before the marquee comes back.
            if hoverReading != nil { hoverExpiry = Date().addingTimeInterval(1.5) }
            return
        }
        hoverExpiry = nil
        hoverReading = reading(for: id)
        mainWindow?.view.setNeedsDisplay(skinRect: Layout.Main.marquee)
        setAnimating(true)
    }

    public func reading(for id: ControlID) -> String? {
        let now = Date()
        switch id {
        case .volume: return Marquee.volumeReading(snapshot, now: now)
        case .balance: return Marquee.balanceReading(snapshot, now: now)
        case .posbar: return Marquee.posbarReading(snapshot, heroIndex: heroIndex, now: now)
        case .kbps: return Marquee.burnReading(snapshot)
        case .khz: return Marquee.activeSessionsReading(snapshot)
        case .monoster: return Marquee.sourcesReading(snapshot)
        case .visualizer: return Marquee.visualizerReading()
        case .eqPreamp: return Marquee.eqPreampReading(snapshot)
        default:
            if let i = id.eqBandIndex {
                let bands = EQModel.bands(snapshot, range: prefs.eqRange, measure: prefs.eqMeasure,
                                          relative: prefs.eqRelative)
                guard i < bands.count else { return nil }
                let b = bands[i]
                return Marquee.eqBandReading(label: b.label, tokens: b.tokens, cost: b.cost)
            }
            return nil
        }
    }

    /// Dragging on the marquee scrubs the text (SPEC 2.1).
    public func beginMarqueeScrub() { marqueeScrubAnchor = marqueeOffset }

    public func scrubMarquee(byPixels dx: CGFloat) {
        guard !marqueeText.isEmpty else { return }
        let width = Double(Marquee.scrollWidth(marqueeText))
        marqueeOffset = (marqueeScrubAnchor - Double(dx)).truncatingRemainder(dividingBy: width)
        if marqueeOffset < 0 { marqueeOffset += width }
        mainWindow.view.setNeedsDisplay(skinRect: Layout.Main.marquee)
    }

    // MARK: - Skins

    public func loadSkin(at url: URL, install: Bool) {
        let target = install ? SkinCatalog.install(url) : url
        do {
            let loaded = try SkinLoader.load(url: target)
            skin = loaded
            skinLoadError = nil
            prefs.skinPath = target.path
            applySkinEverywhere()
        } catch {
            skinLoadError = "\(target.lastPathComponent): \(error)"
            NSSound.beep()
        }
    }

    public func reloadSkin() {
        let loaded = SkinCatalog.load(prefs.effectiveSkinSpec)
        skin = loaded.skin
        skinLoadError = loaded.error
        applySkinEverywhere()
    }

    private func applySkinEverywhere() {
        mainWindow?.skinChanged()
        equalizer?.skinChanged()
        playlist?.skinChanged()
    }

    public func presentLoadSkinPanel() {
        let panel = NSOpenPanel()
        panel.title = "Load Skin"
        panel.allowedContentTypes = [UTType(filenameExtension: "wsz"), UTType.zip].compactMap { $0 }
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = ResourceLocator.userSkinsDirectory
        if panel.runModal() == .OK, let url = panel.url {
            loadSkin(at: url, install: true)
        }
    }

    public func openSkinsFolder() {
        NSWorkspace.shared.open(ResourceLocator.ensureUserSkinsDirectory())
    }

    // MARK: - Panels

    public func showInfoPanel() {
        InfoPanel.show(app: self)
    }

    public func showAbout() {
        InfoPanel.showAbout(app: self)
    }

    // MARK: - Window positions

    /// True while `start()` is placing the windows. Moving one window fires `windowDidMove`,
    /// which would otherwise save the *other* two at the (0, 0) they were created at - and a
    /// saved (0, 0) then survives every future launch.
    private var isRestoringLayout = false

    private func restoreWindowPositions() {
        isRestoringLayout = true
        defer { isRestoringLayout = false }
        // All three origins or none: a half-restored layout scatters the group.
        if let m = prefs.origin(.main), let e = prefs.origin(.equalizer), let p = prefs.origin(.playlist) {
            mainWindow.window.setFrameOrigin(m)
            equalizer.window.setFrameOrigin(e)
            playlist.window.setFrameOrigin(p)
        } else {
            docking.applyDefaultLayout()
        }
        clampOnScreen()
    }

    public func saveWindowPositions() {
        guard !isRestoringLayout, let mainWindow else { return }
        prefs.setOrigin(mainWindow.window.frame.origin, for: .main)
        if let eq = equalizer { prefs.setOrigin(eq.window.frame.origin, for: .equalizer) }
        if let pl = playlist { prefs.setOrigin(pl.window.frame.origin, for: .playlist) }
    }

    /// Put the group back on a screen if a display was unplugged or rearranged since the positions
    /// were saved.
    ///
    /// Two things matter here. A window counts as on-screen when it intersects *any* screen, not
    /// just `NSScreen.main` - otherwise a perfectly good layout on a second display gets yanked
    /// across the moment the primary display changes. And the whole group is moved by one shared
    /// delta, so a rescue never scatters windows that were docked together.
    private func clampOnScreen() {
        let windows = [mainWindow?.window, equalizer?.window, playlist?.window].compactMap { $0 }
        guard !windows.isEmpty else { return }
        let screens = NSScreen.screens.map { $0.visibleFrame }
        guard let home = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }

        func isOnScreen(_ f: CGRect) -> Bool {
            screens.contains { $0.intersects(f.insetBy(dx: -1, dy: -1)) }
        }
        // Only step in when *nothing* is reachable; a partly off-screen stack is the user's choice.
        guard !windows.contains(where: { isOnScreen($0.frame) }) else { return }

        let anchor = mainWindow?.window.frame ?? windows[0].frame
        let target = CGPoint(x: home.minX + 40, y: home.maxY - anchor.height - 40)
        let delta = CGPoint(x: target.x - anchor.minX, y: target.y - anchor.minY)
        for w in windows {
            w.setFrameOrigin(CGPoint(x: w.frame.minX + delta.x, y: w.frame.minY + delta.y))
        }
    }

    // MARK: - Menu

    public func showOptionsMenu(at point: NSPoint, in view: NSView) {
        let menu = OptionsMenu.build(app: self)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    public func quit() {
        stopAndSave()
        NSApp.terminate(nil)
    }
}
