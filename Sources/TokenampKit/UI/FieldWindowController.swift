import AppKit
import CoreGraphics
import Foundation

/// The "Token Flow" window (SPEC 2.9): a resizable generic-frame window whose well holds the
/// phosphor field.
///
/// It owns the persistence buffer, because the buffer *is* the state that survives between frames -
/// the tail, the fading pulses, the last position of the beam. Everything else in the window is a
/// pure function of the snapshot.
public final class FieldWindowController: NSObject, SkinViewDelegate, NSWindowDelegate {

    unowned let app: TokenampController
    public let window: SkinWindow
    public let view: SkinView

    private let field: PhosphorField
    private var labels: [FieldLabel] = []
    /// True when `labels` are already written into `image` (see `render`).
    private var labelsBaked = false
    private var image: CGImage?
    private var elapsed: TimeInterval = 0
    private var director = FieldDirector()

    private var scroll = ScrollStepper()

    private var draggingStarted = false
    private var resizing = false
    /// The bottom-right grip is being dragged. Sessions does not refit meanwhile (A7): its cap
    /// depends on this window's height when it hangs below Sessions, and moving this window under
    /// the pointer would throw the grip off. Also checks the button, like `DockingManager.isDragging`,
    /// so a grip drag whose mouse-up never arrived cannot hold auto-fit back for good.
    var isResizing: Bool { resizing && (NSEvent.pressedMouseButtons & 1) != 0 }
    private var resizeStartSize = SkinPair(0, 0)
    private var resizeStartMouse = CGPoint.zero

    private var skinWidth: Int { min(app.prefs.fieldWidth, FieldRenderer.maxSize.w) }
    private var skinHeight: Int { min(app.prefs.fieldHeight, FieldRenderer.maxSize.h) }

    /// What is actually on screen right now: AUTO's choice, or the user's.
    public private(set) var mode: FieldMode

    init(app: TokenampController) {
        self.app = app
        let scale = app.scale
        // A size saved before the window had a ceiling comes back down to it.
        if app.prefs.fieldWidth > FieldRenderer.maxSize.w { app.prefs.fieldWidth = FieldRenderer.maxSize.w }
        if app.prefs.fieldHeight > FieldRenderer.maxSize.h { app.prefs.fieldHeight = FieldRenderer.maxSize.h }
        let size = SkinPair(app.prefs.fieldWidth, app.prefs.fieldHeight)
        mode = app.prefs.fieldMode
        window = SkinWindow(skinSize: size, scale: scale, title: "Token Flow")
        view = SkinView(frame: NSRect(origin: .zero,
                                      size: ScaleModel.contentSize(skin: size, points: scale)))
        let well = FieldRenderer.canvasRect(width: size.w, height: size.h)
        field = PhosphorField(width: well.w, height: well.h)
        super.init()
        director = FieldDirector(start: mode, now: Date())
        view.scale = scale
        view.delegate = self
        view.regions = FieldRenderer.regions(width: size.w, height: size.h)
        window.contentView = view
        window.delegate = self
    }

    func show() {
        window.orderFront(nil)
        view.needsDisplay = true
    }

    func hide() { window.orderOut(nil) }

    var isVisible: Bool { window.isVisible }

    /// On screen and at least partly uncovered: a window behind another one, on another Space or
    /// minimised is `isVisible` all the same, and has nobody to animate for.
    private var isShowing: Bool { window.isVisible && window.occlusionState.contains(.visible) }

    func skinChanged() {
        image = nil
        view.needsDisplay = true
    }

    func applyScale(_ scale: Double) {
        view.scale = scale
        window.setSkinSize(SkinPair(skinWidth, skinHeight), scale: scale)
        view.frame = NSRect(origin: .zero, size: window.frame.size)
        view.needsDisplay = true
    }

    // MARK: - Animation

    /// One frame: fade the field, draw this instant's geometry into it, and hand the view a new
    /// image. Called from the app's single 30 fps clock, and only while the window is on screen.
    func animate(dt: TimeInterval) {
        guard isShowing else { return }
        let now = Date()
        let snapshot = app.snapshot
        let mods = FieldModulators(snapshot: snapshot, now: now)

        let resolved = app.prefs.fieldAuto
            ? director.resolve(snapshot, mods: mods, now: now)
            : app.prefs.fieldMode
        if resolved != mode {
            mode = resolved
            // A configuration change is a different geometry, not a continuation of the old one.
            field.clear()
        }

        elapsed += dt
        field.decay(dt: dt, persistence: mods.tail(for: mode))
        labels = FieldGeometry.draw(mode, into: field, snapshot: snapshot, mods: mods,
                                    span: app.prefs.fieldSpan, flows: app.sessionFlows(now: now),
                                    t: elapsed, now: now, metrics: FieldRenderer.labelMetrics(for: app.skin))
        FieldGeometry.drawGraticule(field, mode, mods)
        // A frame identical to the last one (a settled plot) is not redrawn.
        guard render(pressure: mods.pressure, onlyIfChanged: true) else { return }
        view.setNeedsDisplay(skinRect: FieldRenderer.canvasRect(width: skinWidth, height: skinHeight))
    }

    /// Turn the buffer into the image the view draws, with the labels written into it in skin
    /// pixels: one image to copy per frame rather than one plus a blit for every glyph. False
    /// when `onlyIfChanged` and the frame is the one already on screen.
    @discardableResult
    private func render(pressure: Double, onlyIfChanged: Bool = false) -> Bool {
        let skin = app.skin
        let set = labels
        var baked = false
        let bake: (PhosphorField.Overlay) -> Void = { overlay in
            baked = FieldRenderer.bake(set, skin: skin, into: overlay)
        }
        let next = onlyIfChanged && image != nil
            ? field.makeImageIfChanged(skin: skin, pressure: pressure, overlay: bake)
            : field.makeImage(skin: skin, pressure: pressure, overlay: bake)
        // Labels the frame could not carry are drawn by the view, and may have moved.
        guard let next else { return !baked }
        image = next
        labelsBaked = baked
        return true
    }

    /// The bottom bar quotes the burn rate and the tightest limit; they change with the data, not
    /// with the animation clock, so they get their own small invalidation.
    func refreshReadout() {
        guard window.isVisible else { return }
        view.setNeedsDisplay(skinRect: SpriteRect(0, skinHeight - Layout.Field.bottomHeight,
                                                  skinWidth, Layout.Field.bottomHeight))
    }

    /// Stop empties the display, the way the faceplate visualiser decays to nothing (SPEC 2.1).
    func silence() {
        field.clear()
        labels = []
        render(pressure: 0)
        view.needsDisplay = true
    }

    /// Jump to a settled field, so the window never appears empty.
    ///
    /// This settles *this* window's own buffer, not a throwaway one: painting a settled picture
    /// over an empty accumulator would look right for one frame and then collapse to whatever a
    /// single frame draws, on every configuration change, span change, resize step and skin swap.
    func settle() {
        let now = Date()
        labels = FieldRenderer.settle(into: field, snapshot: app.snapshot, mode: mode,
                                      span: app.prefs.fieldSpan, now: now,
                                      metrics: FieldRenderer.labelMetrics(for: app.skin))
        let mods = FieldModulators(snapshot: app.snapshot, now: now)
        render(pressure: mods.pressure)
        view.needsDisplay = true
    }

    // MARK: - Actions

    func setMode(_ m: FieldMode) {
        app.prefs.fieldMode = m
        app.prefs.fieldAuto = false
        mode = m
        field.clear()
        settle()
        view.needsDisplay = true
    }

    func toggleAuto() {
        app.prefs.fieldAuto.toggle()
        if app.prefs.fieldAuto {
            director = FieldDirector(start: mode, now: Date())
        } else {
            app.prefs.fieldMode = mode
        }
        view.needsDisplay = true
    }

    func setSpan(_ s: FieldSpan) {
        app.prefs.fieldSpan = s
        field.clear()
        settle()
    }

    /// Every size change keeps the top-left fixed (A6), so the bottom edge moves, and whatever is
    /// docked below this window moves with it - captured before the resize, shifted after it and
    /// saved - exactly as under Sessions (SPEC 2.4, amendment A7).
    private func setSkinSize(_ w: Int, _ h: Int) {
        let sw = FieldRenderer.snapWidth(w), sh = FieldRenderer.snapHeight(h)
        guard sw != skinWidth || sh != skinHeight else { return }
        app.prefs.fieldWidth = sw
        app.prefs.fieldHeight = sh
        let below = app.docking.captureBelow(window)
        window.setSkinSize(SkinPair(sw, sh), scale: app.scale)
        view.frame = NSRect(origin: .zero, size: window.frame.size)
        view.regions = FieldRenderer.regions(width: sw, height: sh)
        let well = FieldRenderer.canvasRect(width: sw, height: sh)
        field.resize(width: well.w, height: well.h)
        settle()
        if app.docking.follow(below, heightChangeOf: window) { app.saveWindowPositions() }
    }

    // MARK: - SkinViewDelegate

    public func skinViewDraw(_ view: SkinView, canvas: SkinCanvas) {
        var s = app.viewState()
        s.pressed = view.pressedIDs
        s.hover = view.hoverID
        s.fieldMode = mode
        s.fieldWidth = skinWidth
        s.fieldHeight = skinHeight
        FieldRenderer.draw(canvas, skin: app.skin, snapshot: app.snapshot, state: s,
                           field: image, labels: labelsBaked ? [] : labels)
    }

    public func skinView(_ view: SkinView, didPress id: ControlID, at point: CGPoint, clickCount: Int) {
        guard id == .fieldResize else { return }
        resizing = true
        resizeStartSize = SkinPair(skinWidth, skinHeight)
        resizeStartMouse = NSEvent.mouseLocation
    }

    public func skinView(_ view: SkinView, didDrag id: ControlID, to point: CGPoint) {
        guard resizing else { return }
        // The window's top-left is fixed, so dragging right and down grows it (screen y grows up).
        let now = NSEvent.mouseLocation
        let dx = Int(((now.x - resizeStartMouse.x) / CGFloat(app.scale)).rounded())
        let dy = Int(((resizeStartMouse.y - now.y) / CGFloat(app.scale)).rounded())
        setSkinSize(resizeStartSize.w + dx, resizeStartSize.h + dy)
    }

    public func skinView(_ view: SkinView, didRelease id: ControlID, at point: CGPoint, inside: Bool) {
        let wasResizing = resizing
        resizing = false
        if wasResizing {
            // The room under Sessions changed when this window hangs below it: auto-fit catches up
            // now that the grip is let go (A7), rather than at whichever publish comes next.
            app.playlist.refit()
            app.saveWindowPositions()
        }
        guard inside else { return }
        switch id {
        case .fieldClose:
            hide()
            app.prefs.fieldOpen = false
            app.mainWindow.view.needsDisplay = true
        case .fieldLamp:
            toggleAuto()
        case .fieldCanvas:
            // Clicking the field steps to the next configuration, the way clicking the faceplate
            // visualiser cycles it.
            guard !wasResizing else { return }
            setMode(mode.next)
        default:
            break
        }
    }

    /// The wheel steps the STRATA span. A mouse wheel steps once per notch; a trackpad swipe
    /// arrives as a stream of small deltas followed by momentum, and steps once per gesture once
    /// it has travelled far enough - otherwise one flick would cycle through every span.
    public func skinView(_ view: SkinView, scrollBy delta: CGFloat) {
        guard mode == .strata else { return }
        let event = NSApp.currentEvent
        let input: ScrollStepper.Input
        if let event, event.type == .scrollWheel {
            input = ScrollStepper.Input(delta: Double(delta),
                                        precise: event.hasPreciseScrollingDeltas,
                                        began: event.phase.contains(.began) || event.phase.contains(.mayBegin),
                                        ended: event.phase.contains(.ended) || event.phase.contains(.cancelled),
                                        momentum: event.momentumPhase != [])
        } else {
            input = ScrollStepper.Input(delta: Double(delta), precise: false, began: false,
                                        ended: false, momentum: false)
        }
        let step = scroll.feed(input)
        guard step != 0 else { return }
        setSpan(step > 0 ? app.prefs.fieldSpan.previous : app.prefs.fieldSpan.next)
    }

    public func skinView(_ view: SkinView, hoverChanged id: ControlID?) { app.setHover(id) }

    public func skinView(_ view: SkinView, rightClickAt point: CGPoint) {
        let menu = NSMenu()
        menu.addItem(OptionsMenu.header("Configuration"))
        let auto = NSMenuItem(title: "Auto", action: #selector(pickAuto), keyEquivalent: "")
        auto.target = self
        auto.state = app.prefs.fieldAuto ? .on : .off
        menu.addItem(auto)
        for m in FieldMode.allCases {
            let item = NSMenuItem(title: m.title, action: #selector(pickMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.rawValue
            item.state = (!app.prefs.fieldAuto && mode == m) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(OptionsMenu.header("Strata span"))
        for s in FieldSpan.allCases {
            let item = NSMenuItem(title: s.title, action: #selector(pickSpan(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.rawValue
            item.state = app.prefs.fieldSpan == s ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Tokenamp Options\u{2026}", action: nil, keyEquivalent: ""))
        menu.items.last?.submenu = OptionsMenu.build(app: app)
        menu.popUp(positioning: nil, at: view.menuPoint(point), in: view)
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

    public func skinView(_ view: SkinView, didDropSkinAt url: URL) { app.loadSkin(at: url, install: true) }

    @objc private func pickAuto() { if !app.prefs.fieldAuto { toggleAuto() } }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = FieldMode(rawValue: raw) else { return }
        setMode(m)
    }

    @objc private func pickSpan(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = FieldSpan(rawValue: raw) else { return }
        setSpan(s)
    }

    // MARK: - NSWindowDelegate

    public func windowDidBecomeKey(_ notification: Notification) { view.needsDisplay = true }
    public func windowDidResignKey(_ notification: Notification) {
        view.clearPressed()
        view.needsDisplay = true
    }
    public func windowDidMove(_ notification: Notification) { app.saveWindowPositions() }

    /// Uncovered again: the buffer stopped while nobody could see it, so bring it straight to a
    /// settled picture rather than letting it build back up from stale.
    public func windowDidChangeOcclusionState(_ notification: Notification) {
        guard isShowing else { return }
        settle()
    }
}

/// Turns scroll events into span steps (SPEC 2.9: "the wheel changes the STRATA span").
///
/// A classic wheel sends one event per notch, and each notch is one step. A trackpad sends a
/// gesture - a began, a run of small precise deltas, an end - and then a tail of momentum events
/// that are not the user's hand at all. Steps come from the gesture only: the deltas accumulate,
/// and the first time they pass `threshold` the gesture steps once and is spent until the next
/// one begins. Pure, so the self-test can drive it.
public struct ScrollStepper {
    public struct Input {
        public var delta: Double
        public var precise: Bool
        public var began: Bool
        public var ended: Bool
        public var momentum: Bool

        public init(delta: Double, precise: Bool, began: Bool, ended: Bool, momentum: Bool) {
            self.delta = delta
            self.precise = precise
            self.began = began
            self.ended = ended
            self.momentum = momentum
        }
    }

    /// Points of precise travel that count as a deliberate swipe.
    public static let threshold = 24.0

    private var accumulated = 0.0
    private var spent = false

    public init() {}

    /// +1 (wheel up / swipe down the content), -1, or 0 for no step.
    public mutating func feed(_ e: Input) -> Int {
        if e.momentum { return 0 }
        if !e.precise {
            accumulated = 0
            spent = false
            // The same half-line dead zone the wheel always had.
            guard abs(e.delta) > 0.5 else { return 0 }
            return e.delta > 0 ? 1 : -1
        }
        if e.began {
            accumulated = 0
            spent = false
        }
        var step = 0
        if !spent {
            accumulated += e.delta
            if abs(accumulated) >= ScrollStepper.threshold {
                step = accumulated > 0 ? 1 : -1
                spent = true
            }
        }
        if e.ended {
            accumulated = 0
            spent = false
        }
        return step
    }
}
