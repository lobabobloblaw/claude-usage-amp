import AppKit
import Foundation

/// The resizable "Sessions" window (SPEC 2.4): wheel and handle scrolling, row selection,
/// double-click opens the session's cwd, vertical resize in 29 px steps via the bottom-right grip.
public final class PlaylistWindowController: NSObject, SkinViewDelegate, NSWindowDelegate {

    unowned let app: TokenampController
    public let window: SkinWindow
    public let view: SkinView
    /// Scroll position and selection, the latter held by session id (`SessionListState`).
    private var list = SessionListState()
    public var scroll: Int { list.scroll }
    /// The selected session's row in the list as it is now.
    public var selection: Int? { list.selectedIndex(in: rowIDs) }

    private var rowIDs: [String] { app.snapshot.sessionsToday.map { $0.id } }

    private var draggingStarted = false
    private var resizeStartHeight = 0
    private var resizeStartMouseY: CGFloat = 0
    private var resizing = false
    private var scrollDragStartY: CGFloat?
    private var scrollDragStartValue = 0

    private var skinHeight: Int { app.prefs.playlistHeight }
    private var skinWidth: Int { Layout.Playlist.defaultSize.w }

    init(app: TokenampController) {
        self.app = app
        let scale = app.scale
        let size = SkinPair(Layout.Playlist.defaultSize.w, app.prefs.playlistHeight)
        window = SkinWindow(skinSize: size, scale: scale, title: "Sessions")
        view = SkinView(frame: NSRect(origin: .zero, size: ScaleModel.contentSize(skin: size, points: scale)))
        super.init()
        view.scale = scale
        view.delegate = self
        view.regions = PlaylistRenderer.regions(width: size.w, height: size.h)
        window.contentView = view
        window.delegate = self
    }

    func show() {
        window.orderFront(nil)
        view.needsDisplay = true
    }

    func hide() { window.orderOut(nil) }

    /// A new skin can bring a different `plfont` row pitch, so the visible-row count - and with it
    /// the scroll clamp - changes with the skin.
    func skinChanged() {
        clampScroll()
        view.needsDisplay = true
    }

    /// Every publish: the list may have shrunk, re-sorted or lost the selected session.
    func dataChanged() {
        if list.reconcile(ids: rowIDs, visibleRows: visibleRows) { view.needsDisplay = true }
    }

    /// The bottom-right countdown ticks once a second; nothing else in the window does.
    /// It is six glyphs wide (`-03:59`) - invalidating five leaves the last digit stale.
    func refreshMiniTime() {
        let L = Layout.Playlist.self
        view.setNeedsDisplay(skinRect: SpriteRect(skinWidth + L.miniTimeFromBottomRight.a,
                                                  skinHeight + L.miniTimeFromBottomRight.b,
                                                  6 * BitmapFont.glyphWidth, BitmapFont.glyphHeight))
    }

    func applyScale(_ scale: Double) {
        view.scale = scale
        window.setSkinSize(SkinPair(skinWidth, skinHeight), scale: scale)
        view.frame = NSRect(origin: .zero, size: window.frame.size)
        view.needsDisplay = true
    }

    private func setSkinHeight(_ h: Int) {
        let snapped = PlaylistRenderer.snapHeight(h)
        guard snapped != app.prefs.playlistHeight else { return }
        app.prefs.playlistHeight = snapped
        window.setSkinSize(SkinPair(skinWidth, snapped), scale: app.scale)
        view.frame = NSRect(origin: .zero, size: window.frame.size)
        view.regions = PlaylistRenderer.regions(width: skinWidth, height: snapped)
        clampScroll()
        view.needsDisplay = true
    }

    private var rowHeight: Int { app.skin.playlistRowHeight }

    private var visibleRows: Int { PlaylistRenderer.visibleRows(height: skinHeight, rowHeight: rowHeight) }

    private var maxScroll: Int {
        SessionListState.maxScroll(count: app.snapshot.sessionsToday.count, visibleRows: visibleRows)
    }

    private func setScroll(_ value: Int) {
        list.setScroll(value, count: app.snapshot.sessionsToday.count, visibleRows: visibleRows)
    }

    private func clampScroll() { setScroll(scroll) }

    // MARK: - SkinViewDelegate

    public func skinViewDraw(_ view: SkinView, canvas: SkinCanvas) {
        var s = app.viewState()
        s.pressed = view.pressedIDs
        s.hover = view.hoverID
        s.playlistWidth = skinWidth
        s.playlistHeight = skinHeight
        s.playlistScroll = scroll
        s.playlistSelection = selection
        PlaylistRenderer.draw(canvas, skin: app.skin, snapshot: app.snapshot, state: s)
    }

    public func skinView(_ view: SkinView, didPress id: ControlID, at point: CGPoint, clickCount: Int) {
        switch id {
        case .plResize:
            resizing = true
            resizeStartHeight = skinHeight
            resizeStartMouseY = NSEvent.mouseLocation.y
        case .plScroll:
            scrollDragStartY = point.y
            scrollDragStartValue = scroll
        case .plList:
            let index = PlaylistRenderer.rowIndex(at: point, width: skinWidth, height: skinHeight,
                                                  scroll: scroll, count: app.snapshot.sessionsToday.count,
                                                  rowHeight: rowHeight)
            list.select(index: index, in: rowIDs)
            view.needsDisplay = true
            if clickCount == 2, let index, index < app.snapshot.sessionsToday.count {
                openRow(index)
            }
        default:
            break
        }
    }

    public func skinView(_ view: SkinView, didDrag id: ControlID, to point: CGPoint) {
        if resizing {
            // The window's top-left is fixed, so dragging down grows it (screen y grows up).
            let delta = resizeStartMouseY - NSEvent.mouseLocation.y
            setSkinHeight(resizeStartHeight + Int((delta / CGFloat(app.scale)).rounded()))
            return
        }
        if id == .plScroll, let start = scrollDragStartY {
            let track = max(1, skinHeight - Layout.Playlist.titleHeight - Layout.Playlist.bottomHeight - 18)
            let deltaRows = Int(((point.y - start) / CGFloat(track) * CGFloat(max(1, maxScroll))).rounded())
            setScroll(scrollDragStartValue + deltaRows)
            view.needsDisplay = true
        }
    }

    public func skinView(_ view: SkinView, didRelease id: ControlID, at point: CGPoint, inside: Bool) {
        resizing = false
        scrollDragStartY = nil
        guard inside else { return }
        if id == .plClose {
            hide()
            app.prefs.playlistOpen = false
            app.mainWindow.view.needsDisplay = true
        }
    }

    public func skinView(_ view: SkinView, scrollBy delta: CGFloat) {
        guard maxScroll > 0 else { return }
        let step = delta > 0 ? -1 : (delta < 0 ? 1 : 0)
        guard step != 0 else { return }
        setScroll(scroll + step)
        view.needsDisplay = true
    }

    public func skinView(_ view: SkinView, rightClickAt point: CGPoint) {
        let menu = NSMenu()
        for (title, cost) in [("Show Cost", true), ("Show Tokens", false)] {
            let item = NSMenuItem(title: title, action: #selector(setShows(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = cost
            item.state = app.prefs.playlistShowsCost == cost ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let reveal = NSMenuItem(title: "Reveal Selected in Finder", action: #selector(revealSelected), keyEquivalent: "")
        reveal.target = self
        reveal.isEnabled = selection != nil
        menu.addItem(reveal)
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

    // MARK: - Row actions

    private func openRow(_ index: Int) {
        let rows = app.snapshot.sessionsToday
        guard index < rows.count, let cwd = rows[index].cwd else { return }
        let url = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func setShows(_ sender: NSMenuItem) {
        app.setPlaylistShowsCost((sender.representedObject as? Bool) ?? true)
    }

    @objc private func revealSelected() {
        if let selection { openRow(selection) }
    }

    // MARK: - NSWindowDelegate

    public func windowDidBecomeKey(_ notification: Notification) { view.needsDisplay = true }
    public func windowDidResignKey(_ notification: Notification) {
        view.clearPressed()
        view.needsDisplay = true
    }
    public func windowDidMove(_ notification: Notification) { app.saveWindowPositions() }
}
