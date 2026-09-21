import AppKit
import Foundation

/// The 275x116 main window and its 275x14 window-shade form (SPEC 2.1, 2.2).
/// Shade mode reuses the same window, exactly as Winamp does.
public final class MainWindowController: NSObject, SkinViewDelegate, NSWindowDelegate {

    unowned let app: TokenampController
    public let window: SkinWindow
    public let view: SkinView
    public private(set) var isShade = false

    private var marqueeDragStart: CGFloat?

    init(app: TokenampController) {
        self.app = app
        let scale = app.scale
        window = SkinWindow(skinSize: Layout.Main.size, scale: scale, title: "Tokenamp")
        view = SkinView(frame: NSRect(origin: .zero,
                                      size: ScaleModel.contentSize(skin: Layout.Main.size, points: scale)))
        super.init()
        view.scale = scale
        view.delegate = self
        view.regions = MainRenderer.mainRegions()
        window.contentView = view
        window.delegate = self
        applyRegionMask()
    }

    // MARK: - Skin / scale

    func skinChanged() {
        applyRegionMask()
        view.needsDisplay = true
    }

    func applyScale(_ scale: Double) {
        view.scale = scale
        window.setSkinSize(isShade ? Layout.Shade.size : Layout.Main.size, scale: scale)
        view.frame = NSRect(origin: .zero, size: window.frame.size)
        applyRegionMask()
        view.needsDisplay = true
    }

    /// region.txt, when the skin ships one, becomes the window's visible shape (SPEC 3).
    private func applyRegionMask() {
        let kind: SkinRegionKind = isShade ? .windowShade : .normal
        if let region = app.skin.regions[kind], !region.isEmpty {
            view.shapeMask = region.path()
            window.isOpaque = false
            window.backgroundColor = .clear
        } else {
            view.shapeMask = nil
        }
    }

    public func setShade(_ on: Bool, persist: Bool) {
        guard on != isShade else { return }
        // Capture before the window resizes, so anything docked below follows the new bottom edge.
        let before = app.docking.captureLayout()
        isShade = on
        if persist { app.prefs.shadeMode = on }
        window.setSkinSize(on ? Layout.Shade.size : Layout.Main.size, scale: app.scale)
        view.frame = NSRect(origin: .zero, size: window.frame.size)
        view.regions = on ? MainRenderer.shadeRegions() : MainRenderer.mainRegions()
        applyRegionMask()
        view.needsDisplay = true
        app.docking.relayoutDocked(from: before)
        app.saveWindowPositions()
    }

    // MARK: - Animation

    private var lastWorkLED = false

    /// Invalidate only what moved, so a parked window costs almost nothing.
    func animate(visualizerMoved: Bool, marqueeMoved: Bool, digitsChanged: Bool, workLED: Bool) {
        let ledChanged = workLED != lastWorkLED
        lastWorkLED = workLED
        if isShade {
            if visualizerMoved { view.setNeedsDisplay(skinRect: Layout.Shade.miniVisualizer) }
            if digitsChanged {
                view.setNeedsDisplay(skinRect: SpriteRect(Layout.Shade.timeGlyphs[0].x, Layout.Shade.timeGlyphs[0].y,
                                                          40, BitmapFont.glyphHeight))
                view.setNeedsDisplay(skinRect: Layout.Shade.position)
            }
            return
        }
        if visualizerMoved { view.setNeedsDisplay(skinRect: Layout.Main.visualizer) }
        if marqueeMoved { view.setNeedsDisplay(skinRect: Layout.Main.marquee) }
        if digitsChanged {
            view.setNeedsDisplay(skinRect: SpriteRect(Layout.Main.minusSignEx.x, Layout.Main.digits[0].y,
                                                      Layout.Main.digits[3].x + 9 - Layout.Main.minusSignEx.x, 13))
            view.setNeedsDisplay(skinRect: Layout.Main.posbar)
            view.setNeedsDisplay(skinRect: Layout.Main.kbps)
            view.setNeedsDisplay(skinRect: Layout.Main.khz)
        }
        if ledChanged { view.setNeedsDisplay(skinRect: Layout.Main.workIndicator) }
    }

    // MARK: - SkinViewDelegate

    public func skinViewDraw(_ view: SkinView, canvas: SkinCanvas) {
        let state = app.viewState()
        var s = state
        s.pressed = view.pressedIDs
        s.hover = view.hoverID
        s.dirtyRect = view.currentDirtySkinRect
        if isShade {
            s.shadeMode = true
            MainRenderer.drawShade(canvas, skin: app.skin, snapshot: app.snapshot, state: s)
        } else {
            MainRenderer.draw(canvas, skin: app.skin, snapshot: app.snapshot, state: s)
        }
    }

    public func skinView(_ view: SkinView, didPress id: ControlID, at point: CGPoint, clickCount: Int) {
        switch id {
        case .titleBar:
            if clickCount == 2 { app.toggleShade() }
        case .marquee:
            marqueeDragStart = point.x
            app.beginMarqueeScrub()
        default:
            break
        }
    }

    public func skinView(_ view: SkinView, didDrag id: ControlID, to point: CGPoint) {
        if id == .marquee, let start = marqueeDragStart {
            app.scrubMarquee(byPixels: point.x - start)
        }
    }

    public func skinView(_ view: SkinView, didRelease id: ControlID, at point: CGPoint, inside: Bool) {
        marqueeDragStart = nil
        guard inside else { return }
        switch id {
        case .optionsButton:
            app.showOptionsMenu(at: NSPoint(x: 0, y: view.bounds.height), in: view)
        case .minimizeButton:
            window.miniaturize(nil)
        case .shadeButton:
            app.toggleShade()
        case .closeButton:
            app.quit()
        case .previous:
            app.selectHero(HeroTrack.previous(app.heroIndex, count: max(1, app.snapshot.limits.count)))
        case .next:
            app.selectHero(HeroTrack.next(app.heroIndex, count: max(1, app.snapshot.limits.count)))
        case .play:
            app.resumeAndRefresh()
        case .pause:
            app.togglePause()
        case .stop:
            app.setPlayState(.stopped)
        case .eject:
            app.presentLoadSkinPanel()
        case .shuffle:
            app.toggleShuffle()
        case .repeatToggle:
            app.toggleRepeatAlerts()
        case .eqToggle:
            app.toggleEqualizer()
        case .plToggle:
            app.togglePlaylist()
        case .timeDisplay:
            app.toggleTimeMode()
        case .visualizer:
            app.cycleVisualizer()
        case .aboutLogo:
            app.showAbout()
        case ControlID.clutter("O"):
            app.showOptionsMenu(at: NSPoint(x: view.viewPoint(point).x, y: view.bounds.height), in: view)
        case ControlID.clutter("A"):
            app.toggleAlwaysOnTop()
        case ControlID.clutter("I"):
            app.showInfoPanel()
        case ControlID.clutter("D"):
            app.cycleScale()
        case ControlID.clutter("V"):
            app.cycleVisualizer()
        default:
            break
        }
    }

    public func skinView(_ view: SkinView, hoverChanged id: ControlID?) {
        app.setHover(id)
    }

    public func skinView(_ view: SkinView, rightClickAt point: CGPoint) {
        app.showOptionsMenu(at: view.menuPoint(point), in: view)
    }

    public func skinView(_ view: SkinView, dragWindowTo origin: CGPoint) {
        if !draggingStarted {
            draggingStarted = true
            app.docking.beginDrag(anchor: window)
        }
        app.docking.drag(anchor: window, to: origin)
    }

    public func skinViewDidEndWindowDrag(_ view: SkinView) {
        draggingStarted = false
        app.docking.endDrag()
        app.saveWindowPositions()
    }

    public func skinView(_ view: SkinView, didDropSkinAt url: URL) {
        app.loadSkin(at: url, install: true)
    }

    private var draggingStarted = false

    // MARK: - NSWindowDelegate

    public func windowDidBecomeKey(_ notification: Notification) { view.needsDisplay = true }
    public func windowDidResignKey(_ notification: Notification) {
        view.clearPressed()
        view.needsDisplay = true
    }
    public func windowDidMove(_ notification: Notification) { app.saveWindowPositions() }

    /// Dragged onto a display with a different backing factor: re-resolve the scale there so a
    /// skin pixel stays a whole number of device pixels and the art never blurs (SPEC 2.8).
    public func windowDidChangeBackingProperties(_ notification: Notification) {
        app.reconcileScaleWithCurrentScreen()
        view.needsDisplay = true
    }

    public func windowDidChangeScreen(_ notification: Notification) {
        app.reconcileScaleWithCurrentScreen()
    }
}
