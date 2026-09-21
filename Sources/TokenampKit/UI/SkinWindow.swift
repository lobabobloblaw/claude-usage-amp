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

    public init(skinSize: SkinPair, scale: Double, title: String) {
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

    /// Resize around the top-left corner, which is how a Winamp window grows downwards.
    public func setSkinSize(_ size: SkinPair, scale: Double) {
        let newSize = ScaleModel.contentSize(skin: size, points: scale)
        var f = frame
        f.origin.y = f.maxY - newSize.height
        f.size = newSize
        setFrame(f, display: true)
    }

    public var topLeft: CGPoint {
        CGPoint(x: frame.minX, y: frame.maxY)
    }

    public func setTopLeft(_ p: CGPoint) {
        setFrameOrigin(CGPoint(x: p.x, y: p.y - frame.height))
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
