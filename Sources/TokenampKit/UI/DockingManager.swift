import AppKit
import Foundation

/// Magnetic window docking (SPEC 2.7). Owns no windows; it is handed the current set on every
/// drag so windows can come and go. All geometry lives in `Logic/Docking.swift`.
public final class DockingManager {

    public weak var main: SkinWindow?
    public weak var equalizer: SkinWindow?
    public weak var playlist: SkinWindow?
    /// Points per skin pixel (SPEC 2.8).
    public var scale: Double = 2

    /// Offsets of the windows that were docked to the anchor when the drag began.
    private var followers: [(window: SkinWindow, offset: CGPoint)] = []

    public init() {}

    private var allWindows: [SkinWindow] {
        [main, equalizer, playlist].compactMap { $0 }.filter { $0.isVisible }
    }

    private func screenFrame(for window: SkinWindow) -> CGRect? {
        (window.screen ?? NSScreen.main)?.visibleFrame
    }

    /// Remember which windows are docked to `anchor` so they can travel with it.
    public func beginDrag(anchor: SkinWindow) {
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

    /// Default placement: main at the top, EQ under it, playlist under the EQ (SPEC 2.7).
    public func applyDefaultLayout() {
        guard let main else { return }
        let screen = screenFrame(for: main) ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let topLeft = CGPoint(x: screen.minX + 40, y: screen.maxY - 40)
        let stack = Docking.defaultStack(mainOrigin: topLeft, scale: scale,
                                         mainHeight: Layout.Main.size.h,
                                         eqHeight: Layout.EQ.size.h,
                                         playlistHeight: playlistSkinHeight())
        main.setFrameOrigin(stack.main)
        equalizer?.setFrameOrigin(stack.eq)
        playlist?.setFrameOrigin(stack.playlist)
    }

    private func playlistSkinHeight() -> Int {
        guard let playlist else { return Layout.Playlist.defaultSize.h }
        return max(1, Int((playlist.frame.height / CGFloat(max(ScaleModel.minPoints, scale))).rounded()))
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
