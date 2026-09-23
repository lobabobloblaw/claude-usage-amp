import AppKit
import Foundation

/// A borderless, skin-shaped window. Borderless windows refuse key status by default, which would
/// break every click, so `canBecomeKey` is overridden.
///
/// Sizes are `ceil(skin x pointsScale)` (SPEC 2.8): at 1.5x on a Retina screen 275 skin px is
/// 412.5 pt, and the window is 413 pt wide with the spare half-point transparent. Origins are
/// snapped to the device-pixel grid so the art never lands on a half pixel and blurs.
public final class SkinWindow: NSWindow {

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    /// The window's size in skin pixels and the points-scale it is shown at, as last set through
    /// `init` or `setSkinSize` - which is every size change the app makes.
    public private(set) var skinSize: SkinPair
    public private(set) var pointsScale: Double

    /// Brings this window to the front together with the app's other skinned windows, set by the
    /// controller. A click raises only the clicked window on current macOS, which left Sessions and
    /// Token Flow behind other apps while the faceplate came forward; Winamp raised the group.
    public var raiseWithGroup: ((SkinWindow) -> Void)?

    /// Runs just before the window is made key and brought to the front - by Window > Main Window,
    /// the Dock icon or a click - so the controller can first bring a window that is on no screen
    /// back onto one (SPEC 2.7). Bringing it to the front where nobody can see it does nothing.
    public var willMakeKeyAndOrderFront: ((SkinWindow) -> Void)?

    public init(skinSize: SkinPair, scale: Double, title: String) {
        self.skinSize = skinSize
        pointsScale = scale
        let size = ScaleModel.contentSize(skin: skinSize, points: scale)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                   backing: .buffered, defer: false)
        self.title = title
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        animationBehavior = .none
        tabbingMode = .disallowed
    }

    public override func makeKeyAndOrderFront(_ sender: Any?) {
        willMakeKeyAndOrderFront?(self)
        super.makeKeyAndOrderFront(sender)
    }

    /// Resize around the top-left corner, which is how a Winamp window grows downwards. Because
    /// every resize keeps it, the top-left corner is also what gets persisted (`WindowLayout`).
    public func setSkinSize(_ size: SkinPair, scale: Double) {
        skinSize = size
        pointsScale = scale
        let newSize = ScaleModel.contentSize(skin: size, points: scale)
        setFrame(WindowLayout.resized(frame, to: newSize), display: true)
    }

    /// What the art really covers - `skinSize x scale` exactly, from the top-left - which is what
    /// docking snaps and stacks on (SPEC 2.8), not the `ceil()`ed frame.
    public var skinFrame: CGRect {
        WindowLayout.skinRect(frame: frame, skinSize: skinSize, scale: pointsScale)
    }

    public var topLeft: CGPoint {
        WindowLayout.topLeft(of: frame)
    }

    public func setTopLeft(_ p: CGPoint) {
        setFrameOrigin(WindowLayout.origin(topLeft: p, height: frame.height))
    }

    /// Every move goes through here, including drags: quantise to whole device pixels so a skin
    /// pixel is always an exact square of them.
    public override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(SkinWindow.deviceAligned(point, backing: backingFactor))
    }

    public var backingFactor: CGFloat {
        screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    }

    static func deviceAligned(_ p: CGPoint, backing: CGFloat) -> CGPoint {
        let b = max(1, backing)
        return CGPoint(x: (p.x * b).rounded() / b, y: (p.y * b).rounded() / b)
    }
}
