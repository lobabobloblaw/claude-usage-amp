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
    public private(set) var field: FieldWindowController!
    private var statusItem: StatusItemController?
    /// Limit alerts (Repeat). The account's ledger is persisted so a relaunch does not announce
    /// again what it already did; synthetic demo data gets one of its own in memory, so a demo run
    /// never writes made-up limit windows into the real ledger.
    private let accountNotifier: ThresholdNotifier
    private let demoNotifier = ThresholdNotifier()
    private var notifier: ThresholdNotifier { isUsingDemoData ? demoNotifier : accountNotifier }

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
    /// Per-session flow for the connectome, recovered by diffing snapshots (SPEC 2.9).
    private let sessionFlow = SessionFlowTracker()

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
        accountNotifier = ThresholdNotifier(prefs: prefs)
        demoOverride = forceDemo
        let p = providerFactory(forceDemo || prefs.demoData)
        provider = p
        snapshot = p.snapshot
        let loaded = SkinCatalog.load(skinOverride ?? prefs.effectiveSkinSpec)
        skin = loaded.skin
        skinLoadError = loaded.error
        heroIndex = prefs.heroIndex
        visualizerMode = prefs.visualizerMode
        // A `--skin` that loaded is remembered, but only once it has drawn (`start`) - and a path
        // as an absolute one, or a launch from Finder (working directory `/`) could not find it.
        skinPathToRemember = loaded.error == nil
            ? skinOverride.map { Arguments.rememberedSkinSpec($0, currentDirectory: FileManager.default.currentDirectoryPath) }
            : nil
        super.init()
    }

    /// A `--skin` override waiting for the first draw before it becomes the stored skin.
    private var skinPathToRemember: String?

    private var activationObserver: NSObjectProtocol?

    /// Bring every open skinned window to the front, keeping their order among themselves, with
    /// `frontmost` (the clicked one) on top and key. Winamp's windows moved as one stack; macOS
    /// raises only the window that was clicked.
    private func raiseWindowGroup(frontmost: SkinWindow?) {
        let group: [SkinWindow] = [mainWindow?.window, equalizer?.window, playlist?.window, field?.window]
            .compactMap { $0 }.filter { $0.isVisible }
        // `orderedWindows` runs front to back; raise back to front so the order is kept.
        let ordered = NSApp.orderedWindows.compactMap { $0 as? SkinWindow }.filter { w in group.contains { $0 === w } }
        for window in ordered.reversed() where window !== frontmost { window.orderFront(nil) }
        (frontmost ?? mainWindow?.window)?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Lifecycle

    public func start() {
        migrateLegacyWindowPositions()
        scale = resolvedStartScale()
        mainWindow = MainWindowController(app: self)
        equalizer = EqualizerWindowController(app: self)
        playlist = PlaylistWindowController(app: self)
        field = FieldWindowController(app: self)

        docking.main = mainWindow.window
        docking.equalizer = equalizer.window
        docking.playlist = playlist.window
        docking.field = field.window
        docking.scale = scale
        docking.onDragEnd = { [weak self] in
            guard let self else { return }
            if self.scaleReconcilePending { self.reconcileScaleWithCurrentScreen() }
            // The drag may have changed the screen room under Sessions, or what is docked below
            // it (SPEC 2.4, amendment A7).
            self.playlist.refit()
        }
        for window in [mainWindow.window, equalizer.window, playlist.window, field.window] as [SkinWindow] {
            window.raiseWithGroup = { [weak self] clicked in self?.raiseWindowGroup(frontmost: clicked) }
        }
        // Window > Main Window, the Dock icon and coming back to the app all bring the main window
        // to the front; one on a display that has gone is brought back first (SPEC 2.7).
        mainWindow.window.willMakeKeyAndOrderFront = { [weak self] _ in self?.bringMainBackIfLost() }
        // Coming back to the app by any route (a click, the Dock, Cmd-Tab) raises the whole stack.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.raiseWindowGroup(frontmost: NSApp.keyWindow as? SkinWindow)
        }

        // The whole layout is settled before anything is shown, and saved only once it is final:
        // the stored corners and shade state, then what is on no screen or has no place of its own
        // yet, then the scale the main window's screen needs, then the main window's group kept
        // inside that screen (SPEC 2.7, 2.8). The windows about to open count as open meanwhile.
        isRestoringLayout = true
        restoreWindowPositions()
        docking.opening = [mainWindow.window]
            + [(equalizer.window, prefs.eqOpen), (playlist.window, prefs.playlistOpen), (field.window, prefs.fieldOpen)]
                .filter { $0.1 }.map { $0.0 }
        bringLayoutOnScreen()
        docking.opening = []
        isRestoringLayout = false
        applyAlwaysOnTop()

        mainWindow.window.makeKeyAndOrderFront(nil)
        if prefs.eqOpen { equalizer.show() }
        if prefs.playlistOpen { playlist.show() }
        if prefs.fieldOpen { field.show() }
        // Auto-fit only once everything is on screen, so what is docked below Sessions follows it.
        playlist.refit()
        if let path = skinPathToRemember {
            drawVisibleWindowsNow()
            prefs.skinPath = path
            skinPathToRemember = nil
        }
        if prefs.menuBarReadout { setMenuBarReadout(true) }

        provider.onChange = { [weak self] snap in self?.ingest(snap) }
        provider.isLiveEnabled = prefs.liveEnabled
        provider.livePollInterval = prefs.pollInterval
        provider.start()
        ingest(provider.snapshot)
        visualizer.settle(snapshot: snapshot)
        field.settle()

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
        sessionFlow.ingest(snap, now: Date())
        // The hero index is deliberately NOT resolved against this snapshot. The live provider's
        // first publish (and every one while the token is expired) has no limits at all, and
        // clamping to that empty tracklist collapsed the user's pick onto track 1 for good.
        // `HeroTrack.hero` wraps the stored index wherever it is used.
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
        field?.refreshReadout()
        playlist?.dataChanged()
        // Row identity and the active flag are in it: the list re-sorts by activity, and the
        // selection highlight follows its session (and the Current colour its state) only if a
        // re-sort alone redraws.
        let plSig = snap.sessionsToday.map { "\($0.id):\($0.isActive):\($0.costUSD):\($0.tokens.total)" }
            .joined(separator: "|") + "|\(snap.today.costUSD)"
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
            // No tracks, nothing to shuffle through - and nothing to overwrite the stored pick with.
            if !snapshot.limits.isEmpty { stepHero(by: 1) }
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

        let fieldAnimating = (field?.isVisible ?? false) && playState != .stopped
        if fieldAnimating { field.animate(dt: dt) }

        // Idle down when nothing is moving, so a parked app costs ~nothing.
        let busy = visMoved || marqueeMoved || playState == .playing || fieldAnimating
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
        s.fieldIsKey = field?.window.isKeyWindow ?? false
        s.fieldMode = field?.mode ?? prefs.fieldMode
        s.fieldAuto = prefs.fieldAuto
        s.fieldSpan = prefs.fieldSpan
        s.fieldWidth = prefs.fieldWidth
        s.fieldHeight = prefs.fieldHeight
        var latched: Set<String> = prefs.alwaysOnTop ? ["A"] : []
        if field?.isVisible == true { latched.insert("V") }
        s.latchedClutter = latched
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

    /// The transport's prev/next (and Shuffle). With no limits there is no track to step to, and
    /// the stored pick is left alone (`HeroTrack.step`).
    public func stepHero(by delta: Int) {
        guard !snapshot.limits.isEmpty else { return }
        selectHero(HeroTrack.step(heroIndex, by: delta, count: snapshot.limits.count))
    }

    public func selectHero(_ index: Int) {
        heroIndex = snapshot.limits.isEmpty ? index : HeroTrack.resolveIndex(index, count: snapshot.limits.count)
        prefs.heroIndex = heroIndex
        rebuildMarquee()
        marqueeOffset = 0
        mainWindow.view.needsDisplay = true
        equalizer.view.needsDisplay = true
    }

    public func setPlayState(_ s: PlayState) {
        playState = s
        provider.isPaused = (s != .playing)
        if s == .stopped {
            visualizer.silence()
            field?.silence()
        } else {
            field?.settle()
        }
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
            // Enabling the toggle must not announce limits that are already high - in whichever
            // data source is not showing right now either, the next time it does.
            notifier.prime(snapshot: snapshot)
            (notifier === accountNotifier ? demoNotifier : accountNotifier).primeOnNextSnapshot()
            notifier.requestAuthorizationIfPossible()
        }
        mainWindow.view.needsDisplay = true
    }

    public func toggleEqualizer() {
        if isShowing(equalizer.window) {
            equalizer.hide()
        } else {
            placeForOpening(equalizer.window, .equalizer)
            equalizer.show()
        }
        prefs.eqOpen = equalizer.window.isVisible
        saveWindowPositions()
        mainWindow.view.needsDisplay = true
    }

    /// Clutterbar **V** and Windows > Token Flow.
    public func toggleField() {
        if isShowing(field.window) {
            field.hide()
        } else {
            // Place it before it is shown, or a first open flashes at the origin and then jumps.
            placeForOpening(field.window, .field)
            field.settle()
            field.show()
        }
        prefs.fieldOpen = field.isVisible
        saveWindowPositions()
        mainWindow.view.needsDisplay = true
        setAnimating(true)
    }

    /// A window with no stored corner goes to the foot of the column when it is opened, rather
    /// than appearing on top of whatever is already there. So does one whose stored place is on
    /// no screen any more (it was parked on a display that has since been unplugged), or it
    /// would open where nobody can see it. The foot of the column may be past the bottom of the
    /// screen, so the main window's group is then kept on screen (SPEC 2.8) - all before the
    /// window is shown, so it never flashes somewhere else first.
    private func placeForOpening(_ window: SkinWindow, _ key: Preferences.WindowKey) {
        guard WindowLayout.needsPlacementOnOpen(isPlaced: prefs.topLeft(key) != nil,
                                                frame: window.skinFrame, screens: visibleScreenFrames) else { return }
        docking.opening = [window]
        defer { docking.opening = [] }
        docking.placeBelowColumn(window)
        docking.keepGroupOnScreen()
    }

    /// Open and on a screen. A window left open on a display that has since gone is not: choosing
    /// it from the Windows menu brings it back to the foot of the column instead of closing it.
    private func isShowing(_ window: SkinWindow) -> Bool {
        window.isVisible && WindowLayout.isReachable(window.skinFrame, screens: visibleScreenFrames)
    }

    private var visibleScreenFrames: [CGRect] { NSScreen.screens.map { $0.visibleFrame } }

    /// Flow per session id for the connectome, 0...1.
    func sessionFlows(now: Date) -> [String: Double] {
        var out: [String: Double] = [:]
        for row in snapshot.sessionsToday {
            let f = sessionFlow.flow(row.id, now: now)
            if f > 0 { out[row.id] = f }
        }
        return out
    }

    public func togglePlaylist() {
        if isShowing(playlist.window) {
            playlist.hide()
        } else {
            placeForOpening(playlist.window, .playlist)
            playlist.show()
            // The sessions may have changed while it was hidden (SPEC 2.4, amendment A7).
            playlist.refit()
        }
        prefs.playlistOpen = playlist.window.isVisible
        saveWindowPositions()
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
        field?.window.level = level
    }

    /// The screen the main window will land on before it exists: the one holding the stored
    /// corner, else the main screen.
    private func startupScreen() -> NSScreen? {
        if let corner = prefs.topLeft(.main) {
            let probe = WindowLayout.probePoint(topLeft: corner)
            if let s = NSScreen.screens.first(where: { $0.frame.contains(probe) }) { return s }
        }
        return NSScreen.main
    }

    private func resolvedStartScale() -> Double {
        startScale(on: startupScreen())
    }

    /// The scale a screen gets: the stored preference, or with none stored the default derived
    /// from *that* screen - never from the scale in use (`ScaleModel.resolved`).
    private func startScale(on screen: NSScreen?) -> Double {
        let backing = screen?.backingScaleFactor ?? 1
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return ScaleModel.resolved(stored: prefs.hasStoredScale ? prefs.pointsScale : nil,
                                   visibleFrame: visible, backing: backing)
    }

    /// The main window changed screens in the middle of a window drag; the rescale waits for the
    /// drag to end (`reconcileScaleWithCurrentScreen`).
    private var scaleReconcilePending = false

    /// SPEC 2.8: when the main window is on a screen whose backing factor makes the stored scale
    /// invalid (1.5x on a 1x display), use the nearest valid scale *there* without overwriting the
    /// preference.
    ///
    /// Not in the middle of a drag: resizing then would leave the dragged window's grip and the
    /// followers' docking offsets at the old scale, so the stack jumped against the pointer and a
    /// follower overlapped the main window by the height difference. The drag's end runs it.
    public func reconcileScaleWithCurrentScreen() {
        guard let mainWindow else { return }
        if docking.isDragging {
            scaleReconcilePending = true
            return
        }
        scaleReconcilePending = false
        let resolved = startScale(on: mainWindow.window.screen ?? NSScreen.main)
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
        field.applyScale(points)
        docking.relayoutDocked(from: before)
        // A stack that now runs past the screen's visible frame moves back onto it as one (SPEC
        // 2.8) - before auto-fit measures the room under Sessions, so Sessions keeps the room the
        // move bought it rather than shrinking first.
        docking.keepGroupOnScreen()
        // The screen room in skin pixels changed with the scale, and with it auto-fit's cap.
        playlist.refit()
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
        case .fieldCanvas:
            return Marquee.fieldReading(field?.mode ?? prefs.fieldMode, auto: prefs.fieldAuto,
                                        snapshot: snapshot)
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

    /// Load a skin the user picked or dropped. It is validated before anything else happens (an
    /// install copies only a skin that loads), and it is remembered for the next launch only once
    /// it has drawn: a skin that brought the app down while drawing must not come back on every
    /// launch after it.
    public func loadSkin(at url: URL, install: Bool) {
        let loaded: (skin: Skin, url: URL)
        do {
            loaded = install ? try SkinCatalog.install(url) : (try SkinLoader.load(url: url), url)
        } catch {
            skinLoadError = "\(url.lastPathComponent): \(error)"
            NSSound.beep()
            return
        }
        skin = loaded.skin
        skinLoadError = nil
        applySkinEverywhere()
        drawVisibleWindowsNow()
        prefs.skinPath = loaded.url.path
    }

    /// Draw every open window right now rather than on the next display cycle, so a skin is known
    /// to render before it is remembered.
    private func drawVisibleWindowsNow() {
        let windows: [SkinWindow?] = [mainWindow?.window, equalizer?.window, playlist?.window, field?.window]
        for case let window? in windows where window.isVisible { window.displayIfNeeded() }
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
        field?.skinChanged()
        field?.settle()
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

    /// Positions are stored as top-left corners (`WindowLayout`): every resize keeps a window's
    /// top-left fixed, so a corner saved from the 14-px shade strip, a short Sessions window or
    /// another scale still puts the window back exactly where it was. Runs inside
    /// `isRestoringLayout`, before anything is shown.
    private func restoreWindowPositions() {
        // Everything starts in the default column; stored corners then override it window by
        // window. A window with no corner (the equalizer starts closed and may never have been
        // opened) keeps its default slot.
        docking.applyDefaultLayout()
        // The main window's corner is what says a layout was ever saved; without it the default
        // column stands.
        if let m = prefs.topLeft(.main) {
            mainWindow.window.setTopLeft(m)
            if let e = prefs.topLeft(.equalizer) { equalizer.window.setTopLeft(e) }
            if let p = prefs.topLeft(.playlist) { playlist.window.setTopLeft(p) }
            if let f = prefs.topLeft(.field) { field.window.setTopLeft(f) }
        }
        // Shade keeps the top-left corner, so it can follow the placement. It must come before
        // the on-screen checks, which have to judge the strip, not the full-height window. Nothing
        // is visible yet, so it moves no other window and saves nothing.
        if prefs.shadeMode { mainWindow.setShade(true, persist: false) }
    }

    public func saveWindowPositions() {
        guard !isRestoringLayout, let mainWindow else { return }
        prefs.setTopLeft(mainWindow.window.topLeft, for: .main)
        // A closed window is saved too once it has a place of its own: its corner does not change
        // while it is hidden, except when a rescue carries it along, and that must stick. One
        // that was never placed stays unstored, so its first opening puts it at the foot of the
        // column (SPEC 2.7).
        let others: [(SkinWindow?, Preferences.WindowKey)] = [(equalizer?.window, .equalizer),
                                                              (playlist?.window, .playlist),
                                                              (field?.window, .field)]
        for case let (window?, key) in others where window.isVisible || prefs.topLeft(key) != nil {
            prefs.setTopLeft(window.topLeft, for: key)
        }
    }

    /// Settle the layout on the screens there are (SPEC 2.7, 2.8): bring back what is on no
    /// screen, use the scale the main window's screen needs, and keep the main window's docked
    /// group inside that screen. At launch, and when the main window is found on no screen.
    private func bringLayoutOnScreen() {
        bringLostWindowsBack()
        // The stored corner, or the rescue, may put the main window on a screen with a different
        // backing factor than the one we guessed from; honour that screen without touching the
        // preference. A scale change keeps the group on screen itself.
        reconcileScaleWithCurrentScreen()
        docking.keepGroupOnScreen()
    }

    /// Window > Main Window, the Dock icon and every other route that brings the main window to
    /// the front: a main window on no screen (its display was unplugged while the app ran) is
    /// brought back first, with its docked group, rather than raised where nobody can see it.
    private func bringMainBackIfLost() {
        guard !isRestoringLayout, let mainWindow,
              !WindowLayout.isReachable(mainWindow.window.skinFrame, screens: visibleScreenFrames) else { return }
        bringLayoutOnScreen()
        playlist.refit()
        saveWindowPositions()
    }

    /// Put back on a screen what is on none - a display was unplugged or rearranged since the
    /// layout was saved - and give every open window that has no place of its own one at the foot
    /// of the user's column, not the default column's slot (SPEC 2.7). The decision is
    /// `WindowLayout.rescue`; this only gathers the facts and moves the windows.
    ///
    /// At launch nothing is shown yet, so what is open is what is about to be (`docking.isOpen`):
    /// the equalizer counts only when it will open (its default slot is on the built-in screen),
    /// and Token Flow is placed - and travels with the group - when it will.
    private func bringLostWindowsBack() {
        guard let mainWindow, let equalizer, let playlist, let field else { return }
        // In column order, so windows put at the foot of the column line up the way the default
        // column runs: Sessions, then Token Flow, then the equalizer.
        let windows: [(window: SkinWindow, key: Preferences.WindowKey)] = [
            (mainWindow.window, .main), (playlist.window, .playlist), (field.window, .field),
            (equalizer.window, .equalizer),
        ]
        let slots = windows.map { w, key in
            WindowLayout.Slot(frame: w.skinFrame, isOpen: docking.isOpen(w),
                              isPlaced: w.isVisible || prefs.topLeft(key) != nil)
        }
        guard let home = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame,
              let rescue = WindowLayout.rescue(slots, screens: visibleScreenFrames, home: home) else { return }
        for i in rescue.moves {
            let w = windows[i].window
            w.setTopLeft(CGPoint(x: w.topLeft.x + rescue.offset.dx, y: w.topLeft.y + rescue.offset.dy))
        }
        // One at a time; those still waiting sit in the default column or on no screen, and must
        // not count as the foot of the column.
        var waiting = rescue.strays.map { windows[$0].window }
        while !waiting.isEmpty {
            let w = waiting.removeFirst()
            docking.placeBelowColumn(w, ignoring: waiting)
        }
    }

    /// Builds before top-left corners stored bottom-left origins. Convert them once, at the scale
    /// they were saved at: the one the last launch resolved, by the same rule, on the screen that
    /// holds the old main-window origin. The layout then comes back exactly where it was.
    private func migrateLegacyWindowPositions() {
        guard prefs.hasLegacyOriginsToMigrate else { return }
        let screen = prefs.legacyOrigin(.main).flatMap { origin in
            NSScreen.screens.first(where: { $0.frame.contains(origin) })
        } ?? NSScreen.main
        prefs.migrateLegacyOrigins(scale: startScale(on: screen), shaded: prefs.shadeMode)
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
