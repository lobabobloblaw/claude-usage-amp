import AppKit
import Foundation

/// The 275x116 "Usage Equalizer" window (SPEC 2.3). The sliders are read-only gauges; the
/// interaction is the PRESETS popup, the ON/AUTO toggles and the hover readings.
public final class EqualizerWindowController: NSObject, SkinViewDelegate, NSWindowDelegate {

    unowned let app: TokenampController
    public let window: SkinWindow
    public let view: SkinView
    private var draggingStarted = false

    init(app: TokenampController) {
        self.app = app
        let scale = app.scale
        window = SkinWindow(skinSize: Layout.EQ.size, scale: scale, title: "Usage Equalizer")
        view = SkinView(frame: NSRect(origin: .zero,
                                      size: ScaleModel.contentSize(skin: Layout.EQ.size, points: scale)))
        super.init()
        view.scale = scale
        view.delegate = self
        view.regions = EQRenderer.regions()
        window.contentView = view
        window.delegate = self
        applyRegionMask()
    }

    func show() {
        window.orderFront(nil)
        view.needsDisplay = true
    }

    func hide() { window.orderOut(nil) }

    func skinChanged() {
        applyRegionMask()
        view.needsDisplay = true
    }

    func applyScale(_ scale: Double) {
        view.scale = scale
        window.setSkinSize(Layout.EQ.size, scale: scale)
        view.frame = NSRect(origin: .zero, size: window.frame.size)
        applyRegionMask()
        view.needsDisplay = true
    }

    private func applyRegionMask() {
        if let region = app.skin.regions[.equalizer], !region.isEmpty {
            view.shapeMask = region.path()
        } else {
            view.shapeMask = nil
        }
    }

    // MARK: - SkinViewDelegate

    public func skinViewDraw(_ view: SkinView, canvas: SkinCanvas) {
        var s = app.viewState()
        s.pressed = view.pressedIDs
        s.hover = view.hoverID
        EQRenderer.draw(canvas, skin: app.skin, snapshot: app.snapshot, state: s)
    }

    public func skinView(_ view: SkinView, didPress id: ControlID, at point: CGPoint, clickCount: Int) {}

    public func skinView(_ view: SkinView, didRelease id: ControlID, at point: CGPoint, inside: Bool) {
        guard inside else { return }
        switch id {
        case .eqClose:
            hide()
            app.prefs.eqOpen = false
            app.mainWindow.view.needsDisplay = true
        case .eqOn:
            app.prefs.eqRelative.toggle()
            view.needsDisplay = true
        case .eqAuto:
            app.prefs.eqAuto.toggle()
            view.needsDisplay = true
        case .eqPresets:
            showPresetsMenu(at: point, in: view)
        default:
            break
        }
    }

    public func skinView(_ view: SkinView, hoverChanged id: ControlID?) { app.setHover(id) }

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

    public func skinView(_ view: SkinView, didDropSkinAt url: URL) { app.loadSkin(at: url, install: true) }

    // MARK: - PRESETS popup (range + measure, SPEC 2.3)

    private func showPresetsMenu(at point: CGPoint, in view: NSView) {
        let menu = NSMenu()
        menu.addItem(OptionsMenu.header("Range"))
        for range in EQRange.allCases {
            let item = NSMenuItem(title: range.title, action: #selector(pickRange(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = range.rawValue
            item.state = app.prefs.eqRange == range ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(OptionsMenu.header("Measure"))
        for measure in EQMeasure.allCases {
            let item = NSMenuItem(title: measure.title, action: #selector(pickMeasure(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = measure.rawValue
            item.state = app.prefs.eqMeasure == measure ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: self.view.menuPoint(point), in: view)
    }

    @objc private func pickRange(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let r = EQRange(rawValue: raw) else { return }
        app.prefs.eqRange = r
        view.needsDisplay = true
    }

    @objc private func pickMeasure(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = EQMeasure(rawValue: raw) else { return }
        app.prefs.eqMeasure = m
        view.needsDisplay = true
    }

    // MARK: - NSWindowDelegate

    public func windowDidBecomeKey(_ notification: Notification) { view.needsDisplay = true }
    public func windowDidResignKey(_ notification: Notification) {
        view.clearPressed()
        view.needsDisplay = true
    }
    public func windowDidMove(_ notification: Notification) { app.saveWindowPositions() }
}
