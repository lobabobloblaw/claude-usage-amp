import AppKit
import Foundation

/// Magnetic window docking (SPEC 2.7). Owns no windows; it is handed the current set on every
/// drag so windows can come and go. All geometry lives in `Logic/Docking.swift`.
public final class DockingManager {

    public weak var main: SkinWindow?
    public weak var equalizer: SkinWindow?
    public weak var playlist: SkinWindow?
    public weak var field: SkinWindow?
    /// Points per skin pixel (SPEC 2.8).
    public var scale: Double = 2

    /// Offsets of the windows that were docked to the anchor when the drag began.
    private var followers: [(window: SkinWindow, offset: CGPoint)] = []

    public init() {}

    private var allWindows: [SkinWindow] {
        [main, equalizer, playlist, field].compactMap { $0 }.filter { $0.isVisible }
    }

    private func screenFrame(for window: SkinWindow) -> CGRect? {
        (window.screen ?? NSScreen.main)?.visibleFrame
    }

    /// Remember which windows are docked to `anchor` so they can travel with it.
    ///
    /// Only the main window carries its group (SPEC 2.7). A sub-window that picked up followers
    /// would be impossible to pull out of a docked stack: dragging it would move everything it
    /// touches, so it would never appear to move at all.
    public func beginDrag(anchor: SkinWindow) {
        guard anchor === main else {
            followers = []
            return
        }
        let others = allWindows.filter { $0 !== anchor }
        let frames = others.map { $0.frame }
        let group = Docking.dockedGroup(anchor: anchor.frame, frames: frames)
        followers = group.sorted().map { i in
            (others[i], CGPoint(x: others[i].frame.minX - anchor.frame.minX,
                                y: others[i].frame.minY - anchor.frame.minY))
        }
    }

    public func endDrag() { followers.removeAll() }

    /// Snap `proposed` and move the anchor plus everything docked to it.
    @discardableResult
    public func drag(anchor: SkinWindow, to proposed: CGPoint) -> CGPoint {
        let followerSet = Set(followers.map { ObjectIdentifier($0.window) })
        let others = allWindows.filter { $0 !== anchor && !followerSet.contains(ObjectIdentifier($0)) }
        let candidate = CGRect(origin: proposed, size: anchor.frame.size)
        let snapped = Docking.snap(frame: candidate, to: others.map { $0.frame },
                                   screen: screenFrame(for: anchor),
                                   threshold: Docking.threshold(scale: scale))
        anchor.setFrameOrigin(snapped)
        for f in followers {
            f.window.setFrameOrigin(CGPoint(x: snapped.x + f.offset.x, y: snapped.y + f.offset.y))
        }
        return snapped
    }

    /// Snap a window that is being placed (not dragged), e.g. after a scale change.
    public func settle(_ window: SkinWindow) {
        let others = allWindows.filter { $0 !== window }
        let snapped = Docking.snap(frame: window.frame, to: others.map { $0.frame },
                                   screen: screenFrame(for: window),
                                   threshold: Docking.threshold(scale: scale))
        window.setFrameOrigin(snapped)
    }

    /// Default placement (SPEC 2.7): the main window at the top, Sessions under it, Token Flow
    /// under that. The Usage Equalizer is placed at the foot of the column but starts closed - its
    /// sliders are read-only gauges, so it is the one window that does not earn a place on screen
    /// until it is asked for.
    public func applyDefaultLayout() {
        guard let main else { return }
        let screen = screenFrame(for: main) ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let topLeft = CGPoint(x: screen.minX + 40, y: screen.maxY - 40)
        let column = Docking.defaultColumn(topLeft: topLeft, scale: scale,
                                           heights: [Layout.Main.size.h,
                                                     playlistSkinHeight(),
                                                     fieldSkinHeight(),
                                                     Layout.EQ.size.h])
        main.setFrameOrigin(column[0])
        playlist?.setFrameOrigin(column[1])
        field?.setFrameOrigin(column[2])
        equalizer?.setFrameOrigin(column[3])
    }

    /// Where a window with no stored origin goes when it is opened: at the foot of whatever of the
    /// column is on screen, so it never lands on top of another window.
    public func placeBelowColumn(_ window: SkinWindow) {
        let others = allWindows.filter { $0 !== window }
        guard let lowest = others.min(by: { $0.frame.minY < $1.frame.minY }) else { return }
        window.setTopLeft(CGPoint(x: lowest.frame.minX, y: lowest.frame.minY))
    }

    private func playlistSkinHeight() -> Int {
        guard let playlist else { return Layout.Playlist.defaultSize.h }
        return max(1, Int((playlist.frame.height / CGFloat(max(ScaleModel.minPoints, scale))).rounded()))
    }

    private func fieldSkinHeight() -> Int {
        guard let field else { return Layout.Field.defaultSize.h }
        return max(1, Int((field.frame.height / CGFloat(max(ScaleModel.minPoints, scale))).rounded()))
    }

    // MARK: - Keeping a docked group together across a size or scale change

    /// A snapshot of where everything was before the main window changed size or scale.
    public struct GroupLayout {
        let main: CGRect
        let scale: Double
        let frames: [(window: SkinWindow, frame: CGRect)]
        /// Which of `frames` were docked to the main window (transitively) at capture time.
        let docked: Set<ObjectIdentifier>
    }

    /// Record the current geometry, so `relayoutDocked` can put the docked windows back where they
    /// belong afterwards. Windows the user deliberately parked elsewhere are *not* in `docked`,
    /// and are therefore left exactly where they are (SPEC 2.8: only docked windows re-lay out).
    public func captureLayout() -> GroupLayout? {
        guard let main else { return nil }
        let others = allWindows.filter { $0 !== main }
        let group = Docking.dockedGroup(anchor: main.frame, frames: others.map { $0.frame })
        var docked: Set<ObjectIdentifier> = []
        for i in group where i < others.count { docked.insert(ObjectIdentifier(others[i])) }
        return GroupLayout(main: main.frame, scale: scale,
                      frames: others.map { ($0, $0.frame) }, docked: docked)
    }

    /// Re-place the windows that were docked to the main window, at the new scale. A window that
    /// hung below the main window stays below it; anything else keeps its offset from the main
    /// window's top-left, measured in skin pixels so it survives a scale change.
    public func relayoutDocked(from before: GroupLayout?) {
        guard let before, let main else { return }
        let old = before.main
        let oldScale = CGFloat(max(ScaleModel.minPoints, before.scale))
        let newScale = CGFloat(max(ScaleModel.minPoints, scale))
        let now = main.frame

        // Walk the vertical chain first: whatever sat directly under the previous window goes
        // directly under its new position, so main -> eq -> playlist survives intact.
        var placed: Set<ObjectIdentifier> = []
        var anchorOld = old
        var anchorNew = now
        var progress = true
        while progress {
            progress = false
            for (window, frame) in before.frames {
                let id = ObjectIdentifier(window)
                guard before.docked.contains(id), !placed.contains(id) else { continue }
                guard abs(frame.maxY - anchorOld.minY) <= 1,
                      frame.minX < anchorOld.maxX, anchorOld.minX < frame.maxX else { continue }
                let dxSkin = (frame.minX - anchorOld.minX) / oldScale
                let top = CGPoint(x: anchorNew.minX + dxSkin * newScale, y: anchorNew.minY)
                window.setTopLeft(top)
                placed.insert(id)
                anchorOld = frame
                anchorNew = window.frame
                progress = true
                break
            }
        }

        // Anything else that was docked keeps its skin-space offset from the main window's top-left.
        for (window, frame) in before.frames {
            let id = ObjectIdentifier(window)
            guard before.docked.contains(id), !placed.contains(id) else { continue }
            let dxSkin = (frame.minX - old.minX) / oldScale
            let dySkin = (old.maxY - frame.maxY) / oldScale
            window.setTopLeft(CGPoint(x: now.minX + dxSkin * newScale, y: now.maxY - dySkin * newScale))
        }
    }
}
