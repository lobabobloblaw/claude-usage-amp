import CoreGraphics
import Foundation

/// The medium every Token Flow configuration is drawn in (SPEC 3.3): a vector beam accumulating
/// into a persistence buffer that decays every frame, quantised through the skin's own 24-colour
/// `viscolor.txt` ramp.
///
/// Why a buffer rather than strokes on the canvas: a real vector display is bright where the beam
/// lingers and faint where it flies, and it keeps a fading tail of where it has been. Both fall out
/// of accumulate-and-decay for free, and both are what make an oscilloscope, a histogram and a
/// connectome look like one instrument instead of three charts.
///
/// Every pixel is still a skin pixel in a skin colour, so the field stays inside the pixel world
/// the rest of the app lives in (SPEC 3, "no vector text anywhere"), and a light skin inverts into
/// ink-on-paper by itself because the colours come from the skin, not from the renderer.
public final class PhosphorField {

    /// The live signal. Rendered through the bar ramp, colours 2 (hot) ... 17 (dim).
    public private(set) var beam: [Double]
    /// The echo layer - cache reads, structure, pulses. Rendered through the scope ramp, 18 ... 22.
    public private(set) var ghost: [Double]
    /// Graticule and walls: replaced every frame, never accumulated.
    public private(set) var grid: [Double]

    public private(set) var width: Int
    public private(set) var height: Int

    /// Deposit scale per channel, set from the decay constant so that persistence changes the
    /// length of the tail and not the brightness of a settled field.
    private var beamGain: Double = 1
    private var ghostGain: Double = 1
    /// Reused between frames: at 30 fps a fresh buffer per frame is megabytes a second of churn
    /// for no reason.
    private var pixels: [UInt8]

    /// Energies in `FieldGeometry` are written against this exposure; one knob for the whole field.
    static let exposure = 1.0 / 12

    /// Intensity above which the beam core saturates to the skin's peak colour.
    static let coreThreshold = 1.25

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        let n = self.width * self.height
        beam = .init(repeating: 0, count: n)
        ghost = .init(repeating: 0, count: n)
        grid = .init(repeating: 0, count: n)
        pixels = .init(repeating: 0, count: n * 4)
    }

    public func resize(width w: Int, height h: Int) {
        guard w != width || h != height else { return }
        width = max(1, w)
        height = max(1, h)
        let n = width * height
        beam = .init(repeating: 0, count: n)
        ghost = .init(repeating: 0, count: n)
        grid = .init(repeating: 0, count: n)
        pixels = .init(repeating: 0, count: n * 4)
    }

    public func clear() {
        for i in 0..<beam.count { beam[i] = 0; ghost[i] = 0; grid[i] = 0 }
    }

    /// Fade the field by `dt` seconds. The ghost layer holds roughly twice as long, so the echo
    /// stays legible under a live trace.
    public func decay(dt: TimeInterval, persistence: Double) {
        let tau = max(0.05, persistence)
        let kBeam = exp(-dt / tau)
        let kGhost = exp(-dt / (tau * 2.2))
        beamGain = 1 - kBeam
        ghostGain = 1 - kGhost
        for i in 0..<beam.count {
            beam[i] *= kBeam
            ghost[i] *= kGhost
            grid[i] = 0
        }
    }

    // MARK: - Beam

    public enum Channel { case beam, ghost, grid }

    @inline(__always)
    public func dot(_ x: Double, _ y: Double, _ energy: Double, _ ch: Channel = .beam) {
        guard energy > 0, x > -1, y > -1, x < Double(width), y < Double(height) else { return }
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Double(x0), fy = y - Double(y0)
        deposit(x0, y0, energy * (1 - fx) * (1 - fy), ch)
        deposit(x0 + 1, y0, energy * fx * (1 - fy), ch)
        deposit(x0, y0 + 1, energy * (1 - fx) * fy, ch)
        deposit(x0 + 1, y0 + 1, energy * fx * fy, ch)
    }

    @inline(__always)
    private func deposit(_ x: Int, _ y: Int, _ e: Double, _ ch: Channel) {
        guard x >= 0, y >= 0, x < width, y < height, e > 0 else { return }
        let i = y * width + x
        switch ch {
        case .beam: beam[i] += e * beamGain * PhosphorField.exposure
        case .ghost: ghost[i] += e * ghostGain * PhosphorField.exposure
        case .grid: grid[i] = max(grid[i], e)
        }
    }

    /// One beam segment. `energy` is per unit of path, so a long sweep and a short one read at the
    /// same brightness per pixel - without this the field's exposure would depend on how long each
    /// path happened to be.
    public func segment(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                        _ energy: Double, _ ch: Channel = .beam) {
        let d = max(abs(x1 - x0), abs(y1 - y0))
        let n = max(1, Int(d.rounded(.up)))
        let per = energy * max(d, 0.35) / Double(n)
        for i in 0...n {
            let t = Double(i) / Double(n)
            dot(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, per, ch)
        }
    }

    /// Catmull-Rom through `points`: what makes a trace a curve instead of a bar chart.
    public func curve(_ points: [CGPoint], _ energy: Double, _ ch: Channel = .beam, samples: Int = 6) {
        guard points.count > 1 else { return }
        func at(_ i: Int) -> CGPoint { points[min(points.count - 1, max(0, i))] }
        var prev = points[0]
        for i in 0..<(points.count - 1) {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            for s in 1...samples {
                let t = Double(s) / Double(samples)
                let t2 = t * t, t3 = t2 * t
                let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t
                               + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                               + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t
                               + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                               + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                segment(prev.x, prev.y, x, y, energy, ch)
                prev = CGPoint(x: x, y: y)
            }
        }
    }

    public func arc(centre c: CGPoint, radius r: Double, from a0: Double, to a1: Double,
                    _ energy: Double, _ ch: Channel = .beam) {
        guard r > 0 else { return }
        let n = max(6, Int(abs(a1 - a0) * r))
        var prev: CGPoint?
        for i in 0...n {
            let a = a0 + (a1 - a0) * Double(i) / Double(n)
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if let q = prev { segment(q.x, q.y, p.x, p.y, energy, ch) }
            prev = p
        }
    }

    // MARK: - Compositing

    /// Map both channels through the skin palette into an image the size of the field.
    ///
    /// `pressure` (0...1, the tightest plan limit) biases the whole field toward the hot end of the
    /// bar ramp, so a nearly-spent window looks spent before you read a single number.
    public func makeImage(skin: Skin, pressure: Double, dots: Bool = true) -> CGImage? {
        let vc = skin.visColors
        let bg = vc.rgb[0]
        let dotRGB = vc.rgb[1]
        let core = PhosphorField.coreRGB(vc)
        let hotShift = Int((pressure * pressure * 5).rounded())

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                var col = bg
                if dots, y % 4 == 2, x % 4 == 2 { col = dotRGB }
                let g = grid[i]
                if g > 0.01 { col = PhosphorField.mix(bg, vc.rgb[15], min(1, g * 0.85)) }
                let gh = ghost[i]
                if gh > 0.02 {
                    let t = min(1.0, pow(gh, 0.6))
                    col = PhosphorField.mix(col, vc.rgb[22 - Int((t * 4).rounded())],
                                            min(1, 0.35 + t * 0.65))
                }
                let b = beam[i]
                if b > 0.02 {
                    let t = min(1.0, pow(b, 0.62))
                    let idx = min(17, max(2, 17 - Int((t * 15).rounded()) - hotShift))
                    col = b > PhosphorField.coreThreshold ? core : vc.rgb[idx]
                }
                let o = i * 4
                pixels[o] = 255
                pixels[o + 1] = UInt8(min(255, max(0, col.r)))
                pixels[o + 2] = UInt8(min(255, max(0, col.g)))
                pixels[o + 3] = UInt8(min(255, max(0, col.b)))
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        // `makeImage` copies, so handing it a pointer into the reused buffer is safe.
        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: info) else { return nil }
            return ctx.makeImage()
        }
    }

    /// The colour the beam core saturates to: whichever of the peak colour (23) and the top of the
    /// bar ramp (2) is furthest from the background. On a dark skin that is the white-hot peak; on
    /// a light skin like Bookcloth it is the darkest ink, because a core that saturates *towards*
    /// the paper would read as the trace vanishing.
    static func coreRGB(_ vc: VisColors) -> (r: Int, g: Int, b: Int) {
        let bg = vc.rgb[0]
        func distance(_ c: (r: Int, g: Int, b: Int)) -> Int {
            abs(c.r - bg.r) + abs(c.g - bg.g) + abs(c.b - bg.b)
        }
        return distance(vc.rgb[23]) >= distance(vc.rgb[2]) ? vc.rgb[23] : vc.rgb[2]
    }

    static func mix(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int), _ t: Double)
        -> (r: Int, g: Int, b: Int) {
        let k = min(1, max(0, t))
        return (r: Int((Double(a.r) + (Double(b.r) - Double(a.r)) * k).rounded()),
                g: Int((Double(a.g) + (Double(b.g) - Double(a.g)) * k).rounded()),
                b: Int((Double(a.b) + (Double(b.b) - Double(a.b)) * k).rounded()))
    }
}
