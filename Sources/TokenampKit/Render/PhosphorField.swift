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
///
/// The beam lands in whole pixels. Each sample goes into the one pixel it falls in, and a path is
/// rasterised one pixel per step along its major axis, so a line is exactly one pixel wide. A
/// bilinear splat would give every line a dim two-pixel fringe, and the nearest-neighbour upscale
/// to the screen turns a fringe like that into blur. Glow and tail still come from
/// accumulate-and-decay, which is where a phosphor display gets them.
public final class PhosphorField {

    public private(set) var width: Int
    public private(set) var height: Int

    /// The live signal. Rendered through the bar ramp, colours 2 (hot) ... 17 (dim).
    public var beam: [Double] { Array(UnsafeBufferPointer(start: beamBuf, count: count)) }
    /// The echo layer - cache reads, structure, pulses. Rendered through the scope ramp, 18 ... 22.
    public var ghost: [Double] { Array(UnsafeBufferPointer(start: ghostBuf, count: count)) }
    /// Graticule and walls: replaced every frame, never accumulated.
    public var grid: [Double] { Array(UnsafeBufferPointer(start: gridBuf, count: count)) }

    // The buffers are raw memory the field owns. They are touched per sample, tens of thousands
    // of times a frame, and a Swift array stored in a class pays an exclusivity and a bounds check
    // on every one of those touches: that alone was most of the frame.
    private var count: Int
    private var beamBuf: UnsafeMutablePointer<Double>
    /// Beam energy times the energy-per-unit-path of the line that put it there. `heat / beam` is
    /// the pixel's *line level* - which line it belongs to, as opposed to how bright it is right
    /// now - and that is what picks its hue. Both decay by the same factor, so a fading tail keeps
    /// its line's hue and dims towards the background instead of stepping into another band of
    /// the ramp.
    private var heatBuf: UnsafeMutablePointer<Double>
    private var ghostBuf: UnsafeMutablePointer<Double>
    private var gridBuf: UnsafeMutablePointer<Double>
    /// Reused between frames: at 30 fps a fresh buffer per frame is megabytes a second of churn
    /// for no reason.
    private var pixels: UnsafeMutablePointer<UInt32>
    /// The last frame `makeImageIfChanged` handed out.
    private var previous: UnsafeMutablePointer<UInt32>
    private var hasPrevious = false
    /// Pixel rings by radius (`arc`).
    private var circles: [Int: [(Int, Int)]] = [:]

    /// Deposit scale per channel, set from the decay constant so that persistence changes the
    /// length of the tail and not the brightness of a settled field.
    private var beamGain: Double = 1
    private var ghostGain: Double = 1

    /// Energies in `FieldGeometry` are written against this exposure; one knob for the whole field.
    static let exposure = 1.0 / 12
    /// The echo layer's share of it. With whole-pixel deposits a ring no longer spreads over two
    /// pixels at half strength, so the echo is brought back to the weight it had as a smear.
    static let ghostExposure = exposure * 0.8

    /// Intensity above which the beam core saturates to the skin's peak colour.
    static let coreThreshold = 1.25

    /// The largest buffer the field will allocate, in pixels per side. The window caps its own
    /// size well inside this (`FieldRenderer.maxSize`); this is only the backstop.
    static let maxSide = 4_096

    public init(width: Int, height: Int) {
        self.width = min(PhosphorField.maxSide, max(1, width))
        self.height = min(PhosphorField.maxSide, max(1, height))
        count = self.width * self.height
        beamBuf = PhosphorField.allocate(count)
        heatBuf = PhosphorField.allocate(count)
        ghostBuf = PhosphorField.allocate(count)
        gridBuf = PhosphorField.allocate(count)
        pixels = .allocate(capacity: count)
        pixels.initialize(repeating: 0, count: count)
        previous = .allocate(capacity: count)
        previous.initialize(repeating: 0, count: count)
    }

    deinit {
        beamBuf.deallocate()
        heatBuf.deallocate()
        ghostBuf.deallocate()
        gridBuf.deallocate()
        pixels.deallocate()
        previous.deallocate()
    }

    private static func allocate(_ n: Int) -> UnsafeMutablePointer<Double> {
        let p = UnsafeMutablePointer<Double>.allocate(capacity: n)
        p.initialize(repeating: 0, count: n)
        return p
    }

    public func resize(width w: Int, height h: Int) {
        let nw = min(PhosphorField.maxSide, max(1, w)), nh = min(PhosphorField.maxSide, max(1, h))
        guard nw != width || nh != height else { return }
        beamBuf.deallocate(); heatBuf.deallocate(); ghostBuf.deallocate(); gridBuf.deallocate()
        pixels.deallocate(); previous.deallocate()
        width = nw
        height = nh
        count = nw * nh
        beamBuf = PhosphorField.allocate(count)
        heatBuf = PhosphorField.allocate(count)
        ghostBuf = PhosphorField.allocate(count)
        gridBuf = PhosphorField.allocate(count)
        pixels = .allocate(capacity: count)
        pixels.initialize(repeating: 0, count: count)
        previous = .allocate(capacity: count)
        previous.initialize(repeating: 0, count: count)
        hasPrevious = false
    }

    public func clear() {
        beamBuf.update(repeating: 0, count: count)
        heatBuf.update(repeating: 0, count: count)
        ghostBuf.update(repeating: 0, count: count)
        gridBuf.update(repeating: 0, count: count)
    }

    /// Fade the field by `dt` seconds. The ghost layer holds roughly twice as long, so the echo
    /// stays legible under a live trace.
    ///
    /// For a picture that does not move, one call with the whole run's `dt` followed by one draw
    /// lands exactly where the same run taken frame by frame would: the buffer keeps `k` of what
    /// it had and the draw adds `1 - k` of its settled value, which is the closed form of the
    /// frame-by-frame sum. `FieldRenderer.settle` relies on that.
    public func decay(dt: TimeInterval, persistence: Double) {
        let tau = max(0.05, persistence)
        let kBeam = exp(-dt / tau)
        let kGhost = exp(-dt / (tau * 2.2))
        beamGain = 1 - kBeam
        ghostGain = 1 - kGhost
        let b = beamBuf, q = heatBuf, g = ghostBuf
        for i in 0..<count {
            b[i] *= kBeam
            q[i] *= kBeam
            g[i] *= kGhost
        }
        gridBuf.update(repeating: 0, count: count)
    }

    // MARK: - Beam

    public enum Channel { case beam, ghost, grid }

    /// One sample, into the pixel it falls in. Pixel centres sit on whole coordinates.
    @inline(__always)
    public func dot(_ x: Double, _ y: Double, _ energy: Double, _ ch: Channel = .beam) {
        guard energy > 0, x >= -0.5, y >= -0.5, x < Double(width) - 0.5, y < Double(height) - 0.5
        else { return }
        deposit(Int(x.rounded()), Int(y.rounded()), energy, ch, level: energy)
    }

    /// `level` is the energy per unit path of the line the deposit belongs to, which sets its hue.
    @inline(__always)
    private func deposit(_ x: Int, _ y: Int, _ e: Double, _ ch: Channel, level: Double) {
        guard x >= 0, y >= 0, x < width, y < height, e > 0 else { return }
        let i = y * width + x
        switch ch {
        case .beam:
            let v = e * beamGain * PhosphorField.exposure
            beamBuf[i] += v
            heatBuf[i] += v * level
        case .ghost:
            ghostBuf[i] += e * ghostGain * PhosphorField.ghostExposure
        case .grid:
            gridBuf[i] = max(gridBuf[i], e)
        }
    }

    /// One beam segment. `energy` is per unit of path, so a long sweep and a short one read at the
    /// same brightness per pixel - without this the field's exposure would depend on how long each
    /// path happened to be. Both end pixels are lit.
    public func segment(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                        _ energy: Double, _ ch: Channel = .beam) {
        polyline([CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y1)], energy, ch)
    }

    /// Straight segments joined end to end, rasterised as one path: a pixel where two segments
    /// meet is lit once, not once per segment.
    public func polyline(_ points: [CGPoint], _ energy: Double, _ ch: Channel = .beam) {
        guard energy > 0, let first = points.first, first.x.isFinite, first.y.isFinite else { return }
        var pen = Pen(field: self, energy: energy, channel: ch, start: first)
        for p in points.dropFirst() { pen.line(to: p) }
        pen.finish()
    }

    /// Catmull-Rom through `points`: what makes a trace a curve instead of a bar chart.
    public func curve(_ points: [CGPoint], _ energy: Double, _ ch: Channel = .beam, samples: Int = 6) {
        guard points.count > 1, energy > 0 else { return }
        func at(_ i: Int) -> CGPoint { points[min(points.count - 1, max(0, i))] }
        guard points[0].x.isFinite, points[0].y.isFinite else { return }
        var pen = Pen(field: self, energy: energy, channel: ch, start: points[0])
        for i in 0..<(points.count - 1) {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            // At least one sample every few pixels, so a long span is still a curve and not a
            // polygon of visible chords.
            let span = max(abs(p2.x - p1.x), abs(p2.y - p1.y))
            let n = max(samples, Int((span / 3).rounded(.up)))
            for s in 1...n {
                let t = Double(s) / Double(n)
                let t2 = t * t, t3 = t2 * t
                let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t
                               + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                               + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t
                               + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                               + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                pen.line(to: CGPoint(x: x, y: y))
            }
        }
        pen.finish()
    }

    /// A circle, or the part of one from `a0` to `a1` (radians, y down).
    ///
    /// Drawn as a pixel circle - centre and radius on whole pixels, the classic midpoint
    /// rasterisation - rather than as a chain of rounded points: the ring comes out symmetric and
    /// one pixel thick, and a partial arc lies on exactly the pixels of the full ring under it.
    /// Each pixel carries one unit of path.
    public func arc(centre c: CGPoint, radius r: Double, from a0: Double, to a1: Double,
                    _ energy: Double, _ ch: Channel = .beam) {
        guard r > 0, r < 16_384, energy > 0, c.x.isFinite, c.y.isFinite, a0.isFinite, a1.isFinite
        else { return }
        let lo = min(a0, a1)
        let sweep = abs(a1 - a0)
        guard sweep > 0 else { return }
        let cx = PhosphorField.pixel(c.x), cy = PhosphorField.pixel(c.y)
        let radius = Int(r.rounded())
        guard radius >= 1 else {
            deposit(cx, cy, energy, ch, level: energy)
            return
        }
        let full = sweep >= 2 * .pi - 1e-9
        // Only a ring that can touch the field is worth walking.
        guard cx + radius >= 0, cy + radius >= 0, cx - radius < width, cy - radius < height else { return }

        for (dx, dy) in circle(radius) {
            if !full {
                var d = atan2(Double(dy), Double(dx)) - lo
                d = d.truncatingRemainder(dividingBy: 2 * .pi)
                if d < 0 { d += 2 * .pi }
                guard d <= sweep + 1e-9 else { continue }
            }
            deposit(cx + dx, cy + dy, energy, ch, level: energy)
        }
    }

    /// Offsets of a one-pixel-thick ring of this radius: the midpoint circle, with the few
    /// L-shaped corner pixels it leaves where the octants meet taken out. Cached per radius.
    private func circle(_ radius: Int) -> [(Int, Int)] {
        if let hit = circles[radius] { return hit }
        let side = 2 * radius + 3
        func key(_ dx: Int, _ dy: Int) -> Int { (dy + radius + 1) * side + dx + radius + 1 }
        var points: [(Int, Int)] = []
        var lit = Set<Int>()
        func add(_ dx: Int, _ dy: Int) {
            if lit.insert(key(dx, dy)).inserted { points.append((dx, dy)) }
        }
        var x = radius, y = 0, err = 1 - radius
        while x >= y {
            add(x, y); add(-x, -y); add(x, -y); add(-x, y)
            add(y, x); add(-y, -x); add(-y, x); add(y, -x)
            y += 1
            if err < 0 {
                err += 2 * y + 1
            } else {
                x -= 1
                err += 2 * (y - x) + 1
            }
        }
        // A pixel with a lit neighbour beside it and another above or below it is the inside of
        // an L; its two neighbours already touch diagonally, so it only thickens the ring.
        let ring = points.filter { p in
            for sx in [-1, 1] { for sy in [-1, 1]
                where lit.contains(key(p.0 + sx, p.1)) && lit.contains(key(p.0, p.1 + sy)) {
                return false
            } }
            return true
        }
        if circles.count > 256 { circles.removeAll() }
        circles[radius] = ring
        return ring
    }

    /// Walks a path through whole pixels and deposits it.
    ///
    /// Each straight piece is stepped one pixel at a time along its major axis between its
    /// rounded end points, so a diagonal stays 8-connected and never breaks up. Every pixel the
    /// path enters takes one unit of path, `energy`: one step along the major axis is one unit,
    /// so a long sweep and a short one read the same per pixel, and a path that crosses itself or
    /// is drawn over again is brighter there - the dwell of a real beam. Sharing a sub-pixel
    /// piece's energy out by length instead would light pixels unevenly depending on where the
    /// samples happened to fall, and the uneven ones read as a dirty fringe. Where a joint would
    /// leave an L-shaped corner - a pixel whose two neighbours along the path already touch
    /// diagonally - the corner pixel is dropped, so a curve is one pixel thick all the way round
    /// rather than doubling up at every change of direction.
    private struct Pen {
        let field: PhosphorField
        let energy: Double
        let channel: Channel
        var at: CGPoint
        // The last two pixels on the path, not yet deposited, because whether the newer one is an
        // L-corner depends on the pixel after it. `held` counts how many of the two are in use.
        var held = 0
        var ax = 0, ay = 0
        var bx = 0, by = 0

        init(field: PhosphorField, energy: Double, channel: Channel, start: CGPoint) {
            self.field = field
            self.energy = energy
            self.channel = channel
            at = start
            ax = PhosphorField.pixel(start.x)
            ay = PhosphorField.pixel(start.y)
            held = 1
        }

        mutating func line(to p: CGPoint) {
            guard p.x.isFinite, p.y.isFinite else { return }
            let x0 = PhosphorField.pixel(at.x), y0 = PhosphorField.pixel(at.y)
            let x1 = PhosphorField.pixel(p.x), y1 = PhosphorField.pixel(p.y)
            at = p
            let dx = x1 - x0, dy = y1 - y0
            let steps = max(abs(dx), abs(dy))
            guard steps > 0 else { return }
            let inv = 1 / Double(steps)
            for k in 1...steps {
                let t = Double(k) * inv
                add(x0 + Int((Double(dx) * t).rounded()), y0 + Int((Double(dy) * t).rounded()))
            }
        }

        @inline(__always)
        private mutating func add(_ x: Int, _ y: Int) {
            if held == 1 {
                guard x != ax || y != ay else { return }
                bx = x; by = y; held = 2
                return
            }
            guard x != bx || y != by else { return }
            // b is an L-corner between a and the new pixel: drop it.
            if abs(ax - x) == 1, abs(ay - y) == 1, abs(bx - ax) + abs(by - ay) == 1 {
                bx = x; by = y
                return
            }
            field.deposit(ax, ay, energy, channel, level: energy)
            ax = bx; ay = by
            bx = x; by = y
        }

        mutating func finish() {
            field.deposit(ax, ay, energy, channel, level: energy)
            if held == 2 { field.deposit(bx, by, energy, channel, level: energy) }
            held = 0
        }
    }

    @inline(__always)
    static func pixel(_ v: Double) -> Int {
        guard v.isFinite else { return Int.min / 4 }
        return Int(max(-1_000_000, min(1_000_000, v)).rounded())
    }

    // MARK: - Compositing

    /// Map both channels through the skin palette into an image the size of the field.
    ///
    /// `pressure` (0...1, the tightest plan limit) biases the whole field toward the hot end of the
    /// bar ramp, so a nearly-spent window looks spent before you read a single number.
    ///
    /// A beam pixel takes its hue from its line's level - the colour that line settles to - and its
    /// brightness from how much energy it holds now: below the line's level it fades towards what
    /// is under it, at the level it is the ramp colour, and piled up past `coreThreshold` it
    /// saturates to the core colour. Mapping energy straight to a ramp index instead would put the
    /// dim pixels of a hot line into a different band of the ramp, and on a banded ramp - red,
    /// orange, green - every line would come out speckled.
    ///
    /// `overlay` writes over the finished frame before it becomes an image: the live window bakes
    /// its labels in there, so a frame reaches the screen as one image instead of one image plus
    /// a blit per glyph.
    public func makeImage(skin: Skin, pressure: Double, dots: Bool = true,
                          overlay: ((Overlay) -> Void)? = nil) -> CGImage? {
        composite(skin: skin, pressure: pressure, dots: dots, overlay: overlay)
        return image()
    }

    /// `makeImage`, or nil when the frame came out exactly as the last one did. A plot that has
    /// settled - STRATA or PHASE between polls, ORBIT between steps of its arm - then costs the
    /// window no redraw at all.
    public func makeImageIfChanged(skin: Skin, pressure: Double, dots: Bool = true,
                                   overlay: ((Overlay) -> Void)? = nil) -> CGImage? {
        composite(skin: skin, pressure: pressure, dots: dots, overlay: overlay)
        let bytes = count * MemoryLayout<UInt32>.size
        if hasPrevious, memcmp(pixels, previous, bytes) == 0 { return nil }
        previous.update(from: pixels, count: count)
        hasPrevious = true
        return image()
    }

    private func composite(skin: Skin, pressure: Double, dots: Bool, overlay: ((Overlay) -> Void)?) {
        let vc = skin.visColors
        let pal = Palette(vc, pressure: pressure)
        let w = width, h = height
        let b = beamBuf, q = heatBuf, g = ghostBuf, gr = gridBuf, px = pixels
        let bgPacked = PhosphorField.pack(pal.bg), dotPacked = PhosphorField.pack(pal.dot)

        for y in 0..<h {
            let dotRow = dots && y % 4 == 2
            let row = y * w
            for x in 0..<w {
                let i = row + x
                let gv = gr[i], gh = g[i], bv = b[i]
                let dot = dotRow && x % 4 == 2
                // Most of the field is empty: background or a graticule dot, nothing to mix.
                if gv <= 0.01, gh <= 0.02, bv <= 0.002 {
                    px[i] = dot ? dotPacked : bgPacked
                    continue
                }
                var col = dot ? pal.dot : pal.bg
                if gv > 0.01 { col = PhosphorField.mix(pal.bg, pal.gridInk, min(1, gv * 0.85)) }
                if gh > 0.02 {
                    let t = min(1.0, pow(gh, 0.6))
                    col = PhosphorField.mix(col, pal.echo[4 - Int((t * 4).rounded())],
                                            min(1, 0.35 + t * 0.65))
                }
                if bv > 0.002 {
                    if bv > PhosphorField.coreThreshold {
                        col = pal.core
                    } else {
                        let level = max(1e-6, q[i] / bv * PhosphorField.exposure)
                        let hue = pal.hue(level)
                        col = bv >= level ? hue : PhosphorField.mix(col, hue, bv / level)
                    }
                }
                px[i] = PhosphorField.pack(col)
            }
        }
        overlay?(Overlay(pixels: px, width: w, height: h))
    }

    private func image() -> CGImage? {
        // The buffer is laid out the way a window's backing store is (32-bit little-endian,
        // alpha first), so drawing a new frame every 30th of a second needs no reshuffle.
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        // `makeImage` copies, so handing it the reused buffer is safe.
        guard let ctx = CGContext(data: pixels, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return nil }
        return ctx.makeImage()
    }

    /// A finished frame in skin pixels, open for writing over (see `makeImage`).
    public struct Overlay {
        let pixels: UnsafeMutablePointer<UInt32>
        public let width: Int
        public let height: Int

        /// Fill a rect, clipped to the field.
        public func fill(x: Int, y: Int, w: Int, h: Int, _ c: (r: Int, g: Int, b: Int)) {
            let x0 = max(0, x), y0 = max(0, y), x1 = min(width, x + w), y1 = min(height, y + h)
            guard x1 > x0, y1 > y0 else { return }
            let v = PhosphorField.pack(c)
            for yy in y0..<y1 { (pixels + yy * width + x0).update(repeating: v, count: x1 - x0) }
        }

        /// One pixel, if it is inside the field.
        @inline(__always)
        public func set(_ x: Int, _ y: Int, _ c: (r: Int, g: Int, b: Int)) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            pixels[y * width + x] = PhosphorField.pack(c)
        }
    }

    /// One opaque pixel in the buffer's layout: A R G B in a little-endian word (bytes B G R A).
    @inline(__always)
    static func pack(_ c: (r: Int, g: Int, b: Int)) -> UInt32 {
        let r = UInt32(min(255, max(0, c.r))), g = UInt32(min(255, max(0, c.g)))
        let b = UInt32(min(255, max(0, c.b)))
        return (0xFF << 24 | r << 16 | g << 8 | b).littleEndian
    }

    /// The colours one frame is composited from, looked up once rather than per pixel.
    private struct Palette {
        let bg: (r: Int, g: Int, b: Int)
        let dot: (r: Int, g: Int, b: Int)
        let gridInk: (r: Int, g: Int, b: Int)
        let core: (r: Int, g: Int, b: Int)
        /// The scope ramp, 18 (hot) ... 22 (dim).
        let echo: [(r: Int, g: Int, b: Int)]
        /// The bar ramp, 2 (hot) ... 17 (dim).
        let ramp: [(r: Int, g: Int, b: Int)]
        let hotShift: Int

        init(_ vc: VisColors, pressure: Double) {
            bg = vc.rgb[0]
            dot = vc.rgb[1]
            gridInk = vc.rgb[15]
            core = PhosphorField.coreRGB(vc)
            echo = Array(vc.rgb[18...22])
            ramp = Array(vc.rgb[2...17])
            hotShift = Int((pressure * pressure * 5).rounded())
            // round(15 t) reaches n where t = (n - 0.5) / 15, and t = level^0.62.
            steps = (1...15).map { pow((Double($0) - 0.5) / 15, 1 / 0.62) }
        }

        /// Levels at which `rampIndex` steps one colour hotter, coolest first.
        let steps: [Double]

        /// The ramp colour a line of this settled level is drawn in (`rampIndex`, by table).
        @inline(__always)
        func hue(_ level: Double) -> (r: Int, g: Int, b: Int) {
            var n = 0
            while n < steps.count, level >= steps[n] { n += 1 }
            return ramp[min(15, max(0, 15 - n - hotShift))]
        }
    }

    /// Bar-ramp index (2 hot ... 17 dim) for a line whose settled intensity is `level`.
    static func rampIndex(level: Double, hotShift: Int) -> Int {
        let t = min(1.0, pow(max(0, level), 0.62))
        return min(17, max(2, 17 - Int((t * 15).rounded()) - hotShift))
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

    @inline(__always)
    static func mix(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int), _ t: Double)
        -> (r: Int, g: Int, b: Int) {
        let k = min(1, max(0, t))
        return (r: Int((Double(a.r) + (Double(b.r) - Double(a.r)) * k).rounded()),
                g: Int((Double(a.g) + (Double(b.g) - Double(a.g)) * k).rounded()),
                b: Int((Double(a.b) + (Double(b.b) - Double(a.b)) * k).rounded()))
    }

    // MARK: - Inspection (self-test)

    /// Beam intensity of one pixel; 0 outside the field.
    func beamAt(_ x: Int, _ y: Int) -> Double {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return beamBuf[y * width + x]
    }

    /// Echo intensity of one pixel; 0 outside the field.
    func ghostAt(_ x: Int, _ y: Int) -> Double {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return ghostBuf[y * width + x]
    }
}
