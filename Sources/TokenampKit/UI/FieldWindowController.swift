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
    private var image: CGImage?
    private var elapsed: TimeInterval = 0
    private var director = FieldDirector()

    private var draggingStarted = false
    private var resizing = false
    private var resizeStartSize = SkinPair(0, 0)
    private var resizeStartMouse = CGPoint.zero

    private var skinWidth: Int { app.prefs.fieldWidth }
    private var skinHeight: Int { app.prefs.fieldHeight }

    /// What is actually on screen right now: AUTO's choice, or the user's.
    public private(set) var mode: FieldMode

    init(app: TokenampController) {
        self.app = app
        let scale = app.scale
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
        guard window.isVisible else { return }
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
        field.decay(dt: dt, persistence: mods.persistence)
        labels = FieldGeometry.draw(mode, into: field, snapshot: snapshot, mods: mods,
                                    span: app.prefs.fieldSpan, flows: app.sessionFlows(now: now),
                                    t: elapsed, now: now)
        FieldGeometry.drawGraticule(field, mode, mods)
        image = field.makeImage(skin: app.skin, pressure: mods.pressure)
        view.setNeedsDisplay(skinRect: FieldRenderer.canvasRect(width: skinWidth, height: skinHeight))
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
        image = field.makeImage(skin: app.skin, pressure: 0)
        labels = []
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
                                      span: app.prefs.fieldSpan, now: now)
        let mods = FieldModulators(snapshot: app.snapshot, now: now)
        image = field.makeImage(skin: app.skin, pressure: mods.pressure)
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

    private func setSkinSize(_ w: Int, _ h: Int) {
        let sw = FieldRenderer.snapWidth(w), sh = FieldRenderer.snapHeight(h)
        guard sw != skinWidth || sh != skinHeight else { return }
        app.prefs.fieldWidth = sw
        app.prefs.fieldHeight = sh
        window.setSkinSize(SkinPair(sw, sh), scale: app.scale)
        view.frame = NSRect(origin: .zero, size: window.frame.size)
        view.regions = FieldRenderer.regions(width: sw, height: sh)
        let well = FieldRenderer.canvasRect(width: sw, height: sh)
        field.resize(width: well.w, height: well.h)
        settle()
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
                           field: image, labels: labels)
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
        if wasResizing { app.saveWindowPositions() }
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

    public func skinView(_ view: SkinView, scrollBy delta: CGFloat) {
        guard mode == .strata, abs(delta) > 0.5 else { return }
        setSpan(delta > 0 ? app.prefs.fieldSpan.previous : app.prefs.fieldSpan.next)
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
}
