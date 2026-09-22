import AppKit
import Foundation

public protocol SkinViewDelegate: AnyObject {
    /// Draw the whole window through the shared renderers.
    func skinViewDraw(_ view: SkinView, canvas: SkinCanvas)
    func skinView(_ view: SkinView, didPress id: ControlID, at point: CGPoint, clickCount: Int)
    func skinView(_ view: SkinView, didRelease id: ControlID, at point: CGPoint, inside: Bool)
    func skinView(_ view: SkinView, didDrag id: ControlID, to point: CGPoint)
    func skinView(_ view: SkinView, hoverChanged id: ControlID?)
    func skinView(_ view: SkinView, rightClickAt point: CGPoint)
    func skinView(_ view: SkinView, scrollBy delta: CGFloat)
    func skinView(_ view: SkinView, dragWindowTo origin: CGPoint)
    func skinViewDidEndWindowDrag(_ view: SkinView)
    func skinView(_ view: SkinView, didDropSkinAt url: URL)
}

public extension SkinViewDelegate {
    func skinView(_ view: SkinView, didDrag id: ControlID, to point: CGPoint) {}
    func skinView(_ view: SkinView, hoverChanged id: ControlID?) {}
    func skinView(_ view: SkinView, scrollBy delta: CGFloat) {}
    func skinViewDidEndWindowDrag(_ view: SkinView) {}
}

/// The one custom view every Tokenamp window uses: a flipped view that draws in skin pixels,
/// hit-tests a declarative region list, tracks pressed/hover state and accepts dropped skins.
public class SkinView: NSView {

    public weak var delegate: SkinViewDelegate?
    /// Points per skin pixel (SPEC 2.8). Fractional on a Retina screen - 1.5 means 3 device
    /// pixels per skin pixel - so it is a Double, not an Int.
    public var scale: Double = 2 { didSet { needsDisplay = true } }
    public var regions: [HitRegion] = []
    /// Region rects are clipped to this shape when the skin ships a region.txt.
    public var shapeMask: CGPath?

    public private(set) var pressedIDs: Set<ControlID> = []
    public private(set) var hoverID: ControlID?

    private var activeRegion: HitRegion?
    private var draggingWindow = false
    private var dragStartMouse: CGPoint = .zero
    private var dragStartOrigin: CGPoint = .zero
    private var trackingArea: NSTrackingArea?

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
    }

    public required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Drawing

    /// The rect being repainted, in skin pixels; valid only inside `draw(_:)`.
    public private(set) var currentDirtySkinRect: SpriteRect?

    public override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let s = CGFloat(scale)
        let skinDirty = SpriteRect(Int((dirtyRect.minX / s).rounded(.down)),
                                   Int((dirtyRect.minY / s).rounded(.down)),
                                   Int((dirtyRect.width / s).rounded(.up)) + 1,
                                   Int((dirtyRect.height / s).rounded(.up)) + 1)
        currentDirtySkinRect = skinDirty
        defer { currentDirtySkinRect = nil }
        cg.saveGState()
        // A flipped NSView already gives us a y-down space; scale it into skin pixels.
        cg.scaleBy(x: s, y: s)
        if let shapeMask {
            cg.addPath(shapeMask)
            cg.clip()
        }
        let canvas = SkinCanvas(ctx: cg, scale: CGFloat(scale))
        delegate?.skinViewDraw(self, canvas: canvas)
        cg.restoreGState()
    }

    /// Redraw only one skin-pixel rect (the animated bits), at device resolution.
    /// Grown by a point on every side: at a fractional scale a skin pixel can straddle the
    /// boundary, and an under-invalidated edge leaves a stale column behind.
    public func setNeedsDisplay(skinRect: SpriteRect) {
        let s = CGFloat(scale)
        let r = NSRect(x: CGFloat(skinRect.x) * s, y: CGFloat(skinRect.y) * s,
                       width: CGFloat(skinRect.w) * s, height: CGFloat(skinRect.h) * s)
        setNeedsDisplay(r.insetBy(dx: -1, dy: -1))
    }

    // MARK: - Hit testing

    public func skinPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / CGFloat(scale), y: p.y / CGFloat(scale))
    }

    /// A skin-pixel point back in view points, for placing menus where the user clicked.
    public func viewPoint(_ skin: CGPoint) -> NSPoint {
        NSPoint(x: skin.x * CGFloat(scale), y: skin.y * CGFloat(scale))
    }

    /// Where `NSMenu.popUp(positioning:at:in:)` should open for a skin-pixel point: the menu's
    /// top-left lands there. `popUp` reads the point in the view's *own* coordinate system, and this
    /// view is flipped, so that is y-down - the same space as `viewPoint`. Flipping it again opened
    /// every context menu mirrored top-to-bottom (a click near the top of Sessions put the menu
    /// near its bottom).
    public func menuPoint(_ skin: CGPoint) -> NSPoint {
        viewPoint(skin)
    }

    public func region(at point: CGPoint) -> HitRegion? {
        // A region.txt shape masks hit-testing as well as drawing (SPEC 3): a click on a
        // transparent part of the window must not land on a control.
        if let shapeMask, !shapeMask.contains(point, using: .winding, transform: .identity) { return nil }
        // Later regions win; the window-drag catch-alls are considered only as a fallback.
        for r in regions.reversed() where r.rect.contains(point) {
            if r.dragsWindow { continue }
            return r
        }
        return regions.first { $0.dragsWindow && $0.rect.contains(point) }
    }

    /// Clicks on a masked-out pixel fall through to whatever is behind the window.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let shapeMask else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let skin = CGPoint(x: local.x / CGFloat(scale), y: local.y / CGFloat(scale))
        guard shapeMask.contains(skin, using: .winding, transform: .identity) else { return nil }
        return super.hitTest(point)
    }

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        if let skinWindow = window as? SkinWindow, let raise = skinWindow.raiseWithGroup {
            raise(skinWindow)
        } else {
            window?.makeKeyAndOrderFront(nil)
        }
        let p = skinPoint(event)
        guard let r = region(at: p) else { return }
        activeRegion = r
        if r.showsPressed {
            pressedIDs.insert(r.id)
            needsDisplay = true
        }
        delegate?.skinView(self, didPress: r.id, at: p, clickCount: event.clickCount)
        if r.dragsWindow, let window {
            draggingWindow = true
            dragStartMouse = NSEvent.mouseLocation
            dragStartOrigin = window.frame.origin
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        if draggingWindow {
            let now = NSEvent.mouseLocation
            let origin = CGPoint(x: dragStartOrigin.x + (now.x - dragStartMouse.x),
                                 y: dragStartOrigin.y + (now.y - dragStartMouse.y))
            delegate?.skinView(self, dragWindowTo: origin)
            return
        }
        guard let r = activeRegion else { return }
        let p = skinPoint(event)
        // Winamp releases a button's pressed sprite when the pointer slides off it, and takes it
        // back when it slides on again.
        if r.showsPressed {
            let inside = r.rect.contains(p)
            if inside, !pressedIDs.contains(r.id) {
                pressedIDs.insert(r.id)
                needsDisplay = true
            } else if !inside, pressedIDs.remove(r.id) != nil {
                needsDisplay = true
            }
        }
        delegate?.skinView(self, didDrag: r.id, to: p)
    }

    public override func mouseUp(with event: NSEvent) {
        if draggingWindow {
            draggingWindow = false
            delegate?.skinViewDidEndWindowDrag(self)
        }
        guard let r = activeRegion else { return }
        let p = skinPoint(event)
        let inside = r.rect.contains(p)
        if pressedIDs.remove(r.id) != nil { needsDisplay = true }
        activeRegion = nil
        delegate?.skinView(self, didRelease: r.id, at: p, inside: inside)
    }

    public override func rightMouseDown(with event: NSEvent) {
        delegate?.skinView(self, rightClickAt: skinPoint(event))
    }

    public override func scrollWheel(with event: NSEvent) {
        delegate?.skinView(self, scrollBy: event.scrollingDeltaY)
    }

    public override func mouseMoved(with event: NSEvent) {
        updateHover(skinPoint(event))
    }

    public override func mouseExited(with event: NSEvent) {
        updateHover(nil)
    }

    private func updateHover(_ point: CGPoint?) {
        let id = point.flatMap { p in region(at: p).flatMap { $0.hasHoverReading ? $0.id : nil } }
        guard id != hoverID else { return }
        hoverID = id
        delegate?.skinView(self, hoverChanged: id)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    public func clearPressed() {
        guard !pressedIDs.isEmpty else { return }
        pressedIDs.removeAll()
        needsDisplay = true
    }

    // MARK: - Drag and drop (SPEC 2.6)

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedSkinURL(sender) != nil ? .copy : []
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedSkinURL(sender) else { return false }
        delegate?.skinView(self, didDropSkinAt: url)
        return true
    }

    private func droppedSkinURL(_ sender: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                               options: options) as? [URL] else { return nil }
        return urls.first(where: { SkinCatalog.isSkinURL($0) })
    }
}
