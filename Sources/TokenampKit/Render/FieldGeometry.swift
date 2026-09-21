import CoreGraphics
import Foundation
import UsageModel

/// A piece of text the field wants set next to something it drew. The phosphor buffer holds no
/// glyphs: labels come back here and `FieldRenderer` sets them in the skin's own bitmap font, so
/// the rule that no system font appears in a skinned window still holds (SPEC 3, amendment A1).
public struct FieldLabel {
    public let text: String
    /// Top-left of the label's ink box in field pixels: the left edge of its first stroke and the
    /// top of its capitals (`FieldLabelMetrics`). With `centred`, `x` is the middle of it instead.
    public let x: Int
    public let y: Int
    /// Dim labels (idle sessions, axis names) take the dim tint. Every label is set over a patch
    /// of the field's background, so no trace runs through its letters.
    public let faint: Bool
    public let centred: Bool

    public init(text: String, x: Int, y: Int, faint: Bool, centred: Bool = false) {
        self.text = text
        self.x = x
        self.y = y
        self.faint = faint
        self.centred = centred
    }
}

/// What the geometry needs to know about the face its labels will be set in. The renderer owns
/// the face (the skin's `plfont`, cut hard - see `FieldRenderer`), and the geometry needs its
/// measurements to keep labels clear of each other and of the things they name.
public struct FieldLabelMetrics {
    /// Ink width of an already-sanitized string.
    public let width: (String) -> Int
    /// Height of the capitals' ink box. A label's `y` is the top of this box.
    public let height: Int
    /// The truncation mark, when the face has one.
    public let ellipsis: String?

    public init(width: @escaping (String) -> Int, height: Int, ellipsis: String?) {
        self.width = width
        self.height = max(1, height)
        self.ellipsis = ellipsis
    }

    /// The classic 5x6 face, for callers that have no skin to hand.
    public static let classic = FieldLabelMetrics(
        width: { max(0, BitmapFont.width(of: $0) - 1) }, height: BitmapFont.glyphHeight,
        ellipsis: "\u{2026}")

    /// `text` cut to fit `maxWidth`: whole if it fits, else shortened with the ellipsis, else cut
    /// bare. A cut never ends on a separator or a dangling period ("FABLE 5." reads as a typo), and
    /// nil means not even a few letters fit.
    public func fit(_ text: String, maxWidth: Int, minLetters: Int = 3) -> String? {
        guard !text.isEmpty else { return nil }
        if width(text) <= maxWidth { return text }
        var chars = Array(text)
        let mark = ellipsis ?? ""
        while chars.count > minLetters {
            chars.removeLast()
            while let last = chars.last, " .-_/:,".contains(last) { chars.removeLast() }
            guard chars.count >= minLetters else { break }
            let candidate = String(chars) + mark
            if width(candidate) <= maxWidth { return candidate }
        }
        return nil
    }
}

/// Where the beam goes for each configuration (SPEC 2.9). Pure: the same inputs always deposit the
/// same energy in the same places, which is what makes `--snapshot` reproducible.
public enum FieldGeometry {

    public static func draw(_ mode: FieldMode, into f: PhosphorField, snapshot s: UsageSnapshot,
                            mods: FieldModulators, span: FieldSpan,
                            flows: [String: Double], t: Double, now: Date,
                            metrics: FieldLabelMetrics = .classic) -> [FieldLabel] {
        switch mode {
        case .scope: drawScope(f, s, mods, now); return []
        case .strata: return drawStrata(f, s, mods, span, now, metrics)
        case .web: return drawWeb(f, s, mods, flows, t, now, metrics)
        case .orbit: return drawOrbit(f, s, mods, t)
        case .phase: return drawPhase(f, s, mods, metrics)
        }
    }

    /// Whether a configuration's picture depends on the animation clock. Only WEB's does (its
    /// pulses travel); every other configuration draws the same thing on every frame of one
    /// instant, which lets `FieldRenderer.settle` take its run in one step. A configuration that
    /// starts reading `t` must be added here.
    public static func moves(_ mode: FieldMode) -> Bool { mode == .web }

    // MARK: - Graticule and wall

    /// Drawn flat every frame, under everything: the instrument's own markings, plus the wall that
    /// closes in as the tightest limit fills.
    public static func drawGraticule(_ f: PhosphorField, _ mode: FieldMode, _ mods: FieldModulators) {
        // The last drawable column and row: a dot at exactly w or h falls outside the field.
        let w = Double(f.width - 1), h = Double(f.height - 1)
        switch mode {
        case .scope, .phase:
            var x = 0.0
            while x < w { f.dot(x, h / 2, 0.55, .grid); x += 3 }
            for k in 0...6 {
                let tx = w * Double(k) / 6
                for dy in -3...3 { f.dot(tx, h / 2 + Double(dy), 0.45, .grid) }
            }
            if mode == .phase {
                var y = 0.0
                while y < h { f.dot(w / 2, y, 0.55, .grid); y += 3 }
            }
        case .strata:
            var x = 0.0
            while x < w { f.dot(x, h - 10, 0.6, .grid); x += 2 }
        case .web, .orbit:
            break
        }

        // The wall. Past half a window it becomes visible, and it closes in as the limit fills, so
        // running out of room looks like running out of room.
        guard mods.pressure > 0.55 else { return }
        let inset = (1 - mods.pressure) * 10
        let e = 0.45 + (mods.pressure - 0.55) / 0.45 * 0.55
        var x = inset
        while x <= w - inset {
            f.dot(x, inset, e, .grid)
            f.dot(x, h - inset, e, .grid)
            x += 1
        }
        var y = inset
        while y <= h - inset {
            f.dot(inset, y, e, .grid)
            f.dot(w - inset, y, e, .grid)
            y += 1
        }
    }

    // MARK: - SCOPE

    /// The bipolar trace over the last 6 min 20 s: what came out above the axis, what went in
    /// below, and the context that was re-read as a mirrored echo behind both.
    static func drawScope(_ f: PhosphorField, _ s: UsageSnapshot, _ m: FieldModulators, _ now: Date) {
        let w = Double(f.width), h = Double(f.height), cy = h / 2
        let lastColumn = w - 1
        let amp = h / 2 - 10
        let fine = s.fine
        let n = fine.count
        guard n > 2, amp > 2 else { return }

        // Envelopes, smoothed across neighbours so the trace has a shape rather than noise.
        func envelope(_ pick: (UsageBucket) -> Double, _ quiet: Double, _ loud: Double) -> [Double] {
            let raw = fine.map { FieldScale.normalise(pick($0), quiet: quiet, loud: loud) }
            var smoothed = [Double](repeating: 0, count: n)
            for i in 0..<n {
                let a: Double = raw[max(0, i - 1)]
                let b: Double = raw[i]
                let c: Double = raw[min(n - 1, i + 1)]
                smoothed[i] = (a + 2 * b + c) / 4
            }
            return smoothed
        }
        let out = envelope({ Double($0.tokens.output) }, 40, 6_000)
        let into = envelope({ Double($0.tokens.input + $0.tokens.cacheWrite) }, 120, 24_000)
        let reread = envelope({ Double($0.tokens.cacheRead) }, 20_000, 1_200_000)

        // How far into the newest 5-second bucket we are. The whole trace slides left by that
        // fraction of a bucket, so the waveform flows past a beam head pinned at the right edge
        // instead of standing still and jumping a whole bucket every five seconds - which is what
        // turns the phosphor tail into a motion trail rather than a smear of the jump.
        let pitch = lastColumn / Double(n - 1)
        let roll: Double
        if let last = fine.last, last.duration > 0 {
            roll = min(1, max(0, now.timeIntervalSince(last.start) / last.duration)) * pitch
        } else {
            roll = 0
        }

        func sample(_ v: [Double], _ u: Double) -> Double {
            let x = u * Double(n - 1)
            let i = min(n - 2, max(0, Int(x)))
            return v[i] + (v[i + 1] - v[i]) * (x - Double(i))
        }

        var up: [CGPoint] = [], down: [CGPoint] = []
        for i in 0..<n {
            let x = lastColumn * Double(i) / Double(n - 1) - roll
            let a = reread[i] * amp * 0.95
            up.append(CGPoint(x: x, y: cy - a))
            down.append(CGPoint(x: x, y: cy + a))
        }
        f.curve(up, m.echo * 6, .ghost)
        f.curve(down, m.echo * 6, .ghost)

        // One trace per active session: three sessions interfere on the same axis, which is what
        // parallel work actually feels like.
        let steps = max(16, Int(w) * 3)
        var trace: [CGPoint] = []
        trace.reserveCapacity(steps + 1)
        for k in 0..<m.beams {
            let share = 1.0 / (1 + 0.55 * Double(m.beams - 1))
            trace.removeAll(keepingCapacity: true)
            for j in 0...steps {
                let x = Double(j) / Double(steps) * (w - 1)
                // Sample the signal where it *is* rather than where it is drawn, and carry the
                // phase with it, so the whole waveform scrolls as one piece.
                let u = min(1, max(0, (x + roll) / lastColumn))
                let phase = (x + roll) * 0.78 + Double(k) * 2.1
                let carrier = sin(phase) * 0.66 + sin(phase * 2.37 + 1.1) * 0.34
                let a = carrier >= 0
                    ? carrier * sample(out, u) * amp * share
                    : carrier * sample(into, u) * amp * share
                trace.append(CGPoint(x: x, y: cy - a))
            }
            f.polyline(trace, 1.6 * m.energy * (1 - 0.14 * Double(k)))
            for i in stride(from: k, to: n, by: 4) where fine[i].messages > 0 {
                let peak = out[i] >= out[max(0, i - 1)] && out[i] >= out[min(n - 1, i + 1)]
                guard peak else { continue }
                let x = lastColumn * Double(i) / Double(n - 1) - roll
                // Hot enough to take a hotter hue than the trace it punches through: a line's
                // colour comes from its own level, not from how much piles up under it.
                f.segment(x, cy - 3, x, cy + 3, 9.0 * m.energy)
            }
        }

        // The beam head at "now", with a short comet behind it: one dot per pixel, so the tail
        // is a solid streak that thins out rather than a dashed one.
        for j in 0..<14 {
            f.dot(w - 1 - Double(j), cy, (12 - Double(j) * 0.72) * m.energy)
        }
    }

    // MARK: - STRATA

    /// The ledger: one riser per bucket up to the fresh-token total, a tick where the output and
    /// input classes end, cache reads as a ghost behind on their own scale, and the pace line.
    static func drawStrata(_ f: PhosphorField, _ s: UsageSnapshot, _ m: FieldModulators,
                           _ span: FieldSpan, _ now: Date,
                           _ metrics: FieldLabelMetrics = .classic) -> [FieldLabel] {
        let w = Double(f.width), h = Double(f.height)
        let lastColumn = w - 1
        let base = h - 10, top = 12.0
        let buckets = span.buckets(s)
        guard buckets.count > 1, base > top else { return [] }
        let cols = buckets.count
        let height = base - top
        // A day bucket holds far more than a minute bucket; scale the axis to the span.
        let loud: Double
        let bucketSeconds: Double
        switch span {
        case .minutes: loud = 600_000; bucketSeconds = 60
        case .hours: loud = 12_000_000; bucketSeconds = 3_600
        case .days: loud = 80_000_000; bucketSeconds = 86_400
        }
        func y(_ v: Double) -> Double { base - FieldScale.normalise(v, quiet: loud / 300, loud: loud) * height }

        // A ledger is a staircase, and a staircase is straight lines. Fed to a spline it would
        // overshoot at every corner: a hook over each riser and a dip below the baseline wherever
        // a bucket is empty.
        let steps = FieldGeometry.staircase

        var ghost: [CGPoint] = []
        for (i, b) in buckets.enumerated() {
            let x = lastColumn * Double(i) / Double(cols - 1)
            let v = FieldScale.normalise(Double(b.tokens.cacheRead), quiet: loud / 8, loud: loud * 44)
            ghost.append(CGPoint(x: x, y: base - v * height))
        }
        f.polyline(steps(ghost), 2.0, .ghost)
        for (i, p) in ghost.enumerated() where i % 3 == 0 {
            f.segment(p.x, p.y, p.x, base, 0.35, .ghost)
        }

        // One riser per bucket, with a tick where each class ends. Three full stacked boundary
        // curves at this column pitch turn into a thicket; a column with two marks on it says the
        // same thing and still reads as a ledger.
        let pitch = lastColumn / Double(cols - 1)
        var outline: [CGPoint] = []
        for (i, b) in buckets.enumerated() {
            let x = lastColumn * Double(i) / Double(cols - 1)
            let out = Double(b.tokens.output)
            let inp = out + Double(b.tokens.input)
            let fresh = inp + Double(b.tokens.cacheWrite)
            let yTotal = y(fresh)
            outline.append(CGPoint(x: x, y: yTotal))
            guard fresh > 0 else { continue }
            f.segment(x, base, x, yTotal, 0.9 * m.energy)
            let tick = max(1.0, pitch * 0.45)
            f.segment(x - tick, y(out), x + tick, y(out), 2.6 * m.energy)
            if inp > out {
                f.segment(x - tick * 0.7, y(inp), x + tick * 0.7, y(inp), 1.2 * m.energy)
            }
        }
        f.polyline(steps(outline), 1.1 * m.energy, .beam)

        // The pace line: what you could spend per bucket for the rest of the window and arrive
        // at the reset exactly at the limit. Columns standing above it are going faster than the
        // window can afford. Drawn only when it can actually be worked out.
        guard let pace = paceLine(s, bucketSeconds: bucketSeconds, now: now) else { return [] }
        let py = y(pace)
        guard py > top - 2, py < base else { return [] }
        var x = 0.0
        while x < w {
            f.segment(x, py, x + 2, py, 2.5 + 8 * max(0, m.pressure - 0.6))
            x += 5
        }
        // The name sits just above the line it names, or just below it when the line runs
        // along the top of the well.
        let above = Int(py.rounded()) - 2 - metrics.height
        let y = above >= 1 ? above : Int(py.rounded()) + 3
        return [FieldLabel(text: "PACE", x: 2, y: y, faint: true)]
    }

    /// Horizontal then vertical through each point: the outline of a bar per point.
    static func staircase(_ pts: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        out.reserveCapacity(pts.count * 2)
        for (i, p) in pts.enumerated() {
            if i > 0 { out.append(CGPoint(x: p.x, y: pts[i - 1].y)) }
            out.append(p)
        }
        return out
    }

    /// Fresh tokens per bucket that would spend exactly the rest of the binding limit over exactly
    /// the rest of its window.
    ///
    /// The limits arrive as a percentage, not as a token budget, so the budget is inferred: what
    /// has been spent inside this window is that percentage of it. That needs a limit with a known
    /// window, some history, and enough of the window used for the inference to mean anything -
    /// otherwise there is no honest line to draw and none is drawn.
    static func paceLine(_ s: UsageSnapshot, bucketSeconds: Double, now: Date) -> Double? {
        guard let limit = s.limits.max(by: { $0.percent < $1.percent }),
              let windowSeconds = limit.windowSeconds, windowSeconds > 0,
              limit.percent >= 2, limit.percent < 100,
              // *This* limit's elapsed time. Taking the session's fraction of a weekly window
              // would swing from zero to seven days every five hours.
              let fraction = limit.elapsedFraction(at: now) else { return nil }
        let elapsed = max(60, fraction * windowSeconds)
        let spent = freshTokens(s, overLast: elapsed)
        guard spent > 0 else { return nil }
        let capacity = spent / (limit.percent / 100)
        let left = max(0, capacity - spent)
        let bucketsLeft = max(1, (windowSeconds - elapsed) / bucketSeconds)
        return left / bucketsLeft
    }

    /// Fresh tokens over the last `seconds`, from whichever series has the resolution for it.
    static func freshTokens(_ s: UsageSnapshot, overLast seconds: TimeInterval) -> Double {
        if seconds <= 3_600 {
            let n = min(s.minutes.count, Int((seconds / 60).rounded(.up)))
            return s.minutes.suffix(n).reduce(0) { $0 + Double($1.tokens.fresh) }
        }
        let n = min(s.hours.count, Int((seconds / 3_600).rounded(.up)))
        return s.hours.suffix(n).reduce(0) { $0 + Double($1.tokens.fresh) }
    }

    // MARK: - WEB

    /// The connectome: a hub, one node per model in play, one per session today, and an edge for
    /// every session to the model it is running on.
    static func drawWeb(_ f: PhosphorField, _ s: UsageSnapshot, _ m: FieldModulators,
                        _ flows: [String: Double], _ t: Double, _ now: Date,
                        _ metrics: FieldLabelMetrics = .classic) -> [FieldLabel] {
        let w = Double(f.width), h = Double(f.height)
        // Whole pixels: every ring is a pixel circle around its node, so the node itself sits on
        // a pixel centre too.
        let centre = CGPoint(x: (w / 2).rounded(.down), y: (h / 2).rounded(.down))
        // Nodes sit on an ellipse inset by enough room for the node itself and its label, so a
        // wide window spreads sideways instead of pushing names off the edge.
        let rx = max(12, w / 2 - 34)
        let ry = max(12, h / 2 - 18)

        // A small well cannot carry a dozen names without the labels colliding, so it carries
        // fewer nodes, shorter names, and names only for the sessions that are actually live.
        let area = f.width * f.height
        let dense = area < 40_000
        let sessions = Array(s.sessionsToday.prefix(dense ? 5 : 8))
        guard !sessions.isEmpty else {
            f.arc(centre: centre, radius: 3.5, from: 0, to: 2 * .pi, 8 * m.energy)
            return []
        }
        let models = Array(Set(sessions.map { $0.model })).sorted()

        var modelAt: [String: CGPoint] = [:]
        for (i, name) in models.enumerated() {
            let a = Double(i) / Double(max(1, models.count)) * 2 * .pi - .pi / 2
            modelAt[name] = CGPoint(x: (centre.x + cos(a) * rx * 0.34).rounded(),
                                    y: (centre.y + sin(a) * ry * 0.34).rounded())
        }

        let hubRadius = 4.5, modelRadius = 2.5
        f.arc(centre: centre, radius: hubRadius, from: 0, to: 2 * .pi, 26 * m.energy)
        f.arc(centre: centre, radius: 2, from: 0, to: 2 * .pi, 18 * m.energy)
        f.dot(centre.x, centre.y, 14 * m.energy)

        for (_, p) in modelAt.sorted(by: { $0.key < $1.key }) {
            f.segment(centre.x, centre.y, p.x, p.y, 9 * m.energy, .ghost)
            f.arc(centre: p, radius: modelRadius, from: 0, to: 2 * .pi, 11 * m.energy)
        }

        // Every node. They hold still: in a field of whole pixels a node that wobbled would
        // leave its ring and every edge doubled up by its own tail, and the pulses already say
        // which sessions are live.
        struct Node {
            let at: CGPoint
            let radius: Double
            let row: SessionRow
            let recency: Double
        }
        var nodes: [Node] = []
        for (i, row) in sessions.enumerated() {
            guard let anchor = modelAt[row.model] else { continue }
            let a = Double(i) / Double(sessions.count) * 2 * .pi + 0.6
            // Live sessions are held in close to the hub; idle ones drift out towards the rim.
            let pull = row.isActive ? 0.72 : 0.97
            let p = CGPoint(x: (centre.x + cos(a) * rx * pull).rounded(),
                            y: (centre.y + sin(a) * ry * pull).rounded())

            let idle = now.timeIntervalSince(row.lastActivity)
            let recency = row.isActive ? 1.0 : max(0.12, 1 - idle / 3_600)
            let flow = flows[row.id] ?? (row.isActive ? 0.25 : 0)
            // An idle session still shows what it is attached to, just faintly.
            let link = max(0.35, recency)

            let mid = CGPoint(x: (p.x + anchor.x) / 2 + (centre.x - (p.x + anchor.x) / 2) * 0.35,
                              y: (p.y + anchor.y) / 2 + (centre.y - (p.y + anchor.y) / 2) * 0.35)
            f.curve([p, mid, anchor], (2.2 + 7 * flow) * m.energy * link, .beam, samples: 8)

            let r = 2 + FieldScale.normalise(Double(row.tokens.total), quiet: 1e5, loud: 6e7) * 6
            f.arc(centre: p, radius: r, from: 0, to: 2 * .pi, (9 + 11 * recency) * m.energy)
            f.dot(p.x, p.y, 12 * recency * m.energy)

            if row.isActive {
                let pulse = (t * 0.9 + Double(i) * 0.31).truncatingRemainder(dividingBy: 1)
                f.arc(centre: p, radius: r + 2 + pulse * 9, from: 0, to: 2 * .pi,
                      (1 - pulse) * 9 * m.energy, .ghost)
            }
            nodes.append(Node(at: p, radius: r.rounded(), row: row, recency: recency))
        }

        // Names. Live sessions first, then the models, then idle sessions from the most recent:
        // when there is not room for everything, the ones that matter least are the ones that go.
        var placer = LabelPlacer(width: f.width, height: f.height, metrics: metrics)
        placer.avoid(centre, radius: hubRadius.rounded())
        for p in modelAt.values { placer.avoid(p, radius: modelRadius.rounded()) }
        for n in nodes { placer.avoid(n.at, radius: n.radius) }

        var labels: [FieldLabel] = []
        let sessionWidth = dense ? max(36, Int(w * 0.3)) : max(40, min(110, Int(w * 0.4)))
        func labelSession(_ n: Node) {
            let name = BitmapFont.sanitize(shortProject(n.row.project))
            let texts = [metrics.fit(name, maxWidth: sessionWidth),
                         metrics.fit(name, maxWidth: sessionWidth * 3 / 5)].compactMap { $0 }
            if let placed = placer.place(texts, near: n.at, radius: n.radius, from: centre,
                                         faint: !n.row.isActive) {
                labels.append(placed)
            }
        }
        for n in nodes where n.row.isActive { labelSession(n) }
        if !dense {
            for (name, p) in modelAt.sorted(by: { $0.key < $1.key }) {
                if let placed = placer.place(FieldGeometry.modelNames(name, metrics: metrics),
                                             near: p, radius: modelRadius.rounded(), from: centre,
                                             faint: true) {
                    labels.append(placed)
                }
            }
            let idle = nodes.filter { !$0.row.isActive }.sorted { $0.recency > $1.recency }
            for n in idle { labelSession(n) }
        }
        return labels
    }

    /// The ways a model can be named, longest first: whole ("FABLE 5.1") while it fits, then the
    /// family alone ("FABLE") - never a version cut short, which would end on a dangling period.
    static func modelNames(_ model: String, metrics: FieldLabelMetrics, maxWidth: Int = 64) -> [String] {
        let whole = BitmapFont.sanitize(model).trimmingCharacters(in: .whitespaces)
        var out: [String] = []
        if !whole.isEmpty, metrics.width(whole) <= maxWidth { out.append(whole) }
        if let space = whole.firstIndex(of: " ") {
            let family = String(whole[..<space])
            if let fitted = metrics.fit(family, maxWidth: maxWidth), !out.contains(fitted) {
                out.append(fitted)
            }
        } else if out.isEmpty, let fitted = metrics.fit(whole, maxWidth: maxWidth) {
            out.append(fitted)
        }
        return out
    }

    /// `fable5dot1/claude-usage-amp` -> `CLAUDE-USAGE-AMP`: the leaf is what identifies the work.
    static func shortProject(_ p: String) -> String {
        (p.split(separator: "/").last.map(String.init) ?? p).uppercased()
    }

    // MARK: - ORBIT

    /// The polar wall: angle is where you are in the window, radius is how hard you were working,
    /// and the ring is the limit. The consumed arc fills it as the window is spent.
    static func drawOrbit(_ f: PhosphorField, _ s: UsageSnapshot, _ m: FieldModulators,
                          _ t: Double) -> [FieldLabel] {
        let w = Double(f.width), h = Double(f.height)
        let centre = CGPoint(x: w / 2, y: h / 2)
        let reach = min(w, h)
        let rSession = reach * 0.30
        let rWeek = reach * 0.42
        let start = -Double.pi / 2

        let sessionPct = (s.limit(.session)?.percent ?? m.pressure * 100) / 100
        let weekPct = (s.limit(.weeklyAll)?.percent ?? 0) / 100

        // The rings are the limits, so they carry the weight of a wall even one pixel thick.
        f.arc(centre: centre, radius: rWeek, from: 0, to: 2 * .pi, 15, .ghost)
        f.arc(centre: centre, radius: rSession, from: 0, to: 2 * .pi, 18, .ghost)

        let hot = 4.5 + 11 * max(0, m.pressure - 0.6)
        if weekPct > 0 {
            f.arc(centre: centre, radius: rWeek, from: start,
                  to: start + 2 * .pi * min(1, weekPct), hot * 1.4)
        }
        f.arc(centre: centre, radius: rSession, from: start,
              to: start + 2 * .pi * min(1, sessionPct), hot * 1.8)

        // The shape of the window so far, inside the session ring.
        // The ring is the whole window, so the trace has to cover everything that has elapsed,
        // not just the last hour: the hour buckets carry the body of it and the minute buckets
        // redraw the final hour in detail on top.
        let window = s.limit(.session)?.windowSeconds ?? 18_000
        let elapsed = max(60, m.phase * window)

        func polar(_ buckets: [UsageBucket], from a0: Double, to a1: Double, groups: Int,
                   quiet: Double, loud: Double, energy: Double) {
            guard buckets.count > 1, groups > 1 else { return }
            let per = Double(buckets.count) / Double(groups)
            var pts: [CGPoint] = []
            for g in 0..<groups {
                let lo = Int(Double(g) * per)
                let hi = max(lo + 1, min(buckets.count, Int(Double(g + 1) * per)))
                var peak = 0.0
                for i in lo..<hi {
                    peak = max(peak, Double(buckets[i].tokens.output + buckets[i].tokens.cacheWrite))
                }
                let u = Double(g) / Double(groups - 1)
                let a = a0 + (a1 - a0) * u
                let r = rSession * (0.34 + 0.58 * FieldScale.normalise(peak, quiet: quiet, loud: loud))
                pts.append(CGPoint(x: centre.x + cos(a) * r, y: centre.y + sin(a) * r))
            }
            f.curve(pts, energy, .beam, samples: 6)
        }

        let nowAngle = start + 2 * .pi * max(0.04, m.phase)
        if elapsed > 3_600 {
            let hoursBack = min(s.hours.count, Int((elapsed / 3_600).rounded(.up)))
            let body = Array(s.hours.suffix(hoursBack))
            polar(body, from: start, to: nowAngle, groups: max(2, min(36, body.count * 4)),
                  quiet: 60_000, loud: 14_000_000, energy: 5 * m.energy)
            let lastHour = nowAngle - (nowAngle - start) * (3_600 / elapsed)
            polar(s.minutes, from: lastHour, to: nowAngle, groups: 30,
                  quiet: 1_500, loud: 300_000, energy: 7 * m.energy)
        } else {
            polar(s.minutes, from: start, to: nowAngle, groups: 36,
                  quiet: 1_500, loud: 300_000, energy: 7 * m.energy)
        }

        let a = start + 2 * .pi * m.phase
        f.segment(centre.x, centre.y, centre.x + cos(a) * rWeek, centre.y + sin(a) * rWeek,
                  22 * m.energy, .ghost)
        f.dot(centre.x + cos(a) * rSession, centre.y + sin(a) * rSession, 22 * m.energy)

        // Near the wall the ring starts to shed sparks where the arc presses against it.
        if m.pressure > 0.85 {
            for k in 0..<28 {
                let ang = start + 2 * .pi * (Double(k) / 28) * sessionPct
                let jitter = 0.6 + Double((k &* 2_654_435_761) % 1_000) / 1_000 * 2.4
                f.dot(centre.x + cos(ang) * (rSession + jitter),
                      centre.y + sin(ang) * (rSession + jitter), 9)
            }
        }
        return []
    }

    // MARK: - PHASE

    /// The return map: the flow now against the flow a little earlier, trailed.
    ///
    /// Plotting two token counts against each other only works while their ratio actually moves;
    /// when the mix is steady the figure collapses onto a line and says nothing. A signal against
    /// its own recent past always has something to say: steady work sits on the diagonal, and
    /// every burst-and-recover cycle throws a loop off it, so the shape is the rhythm of the work
    /// rather than a property of the token mix.
    static func drawPhase(_ f: PhosphorField, _ s: UsageSnapshot, _ m: FieldModulators,
                          _ metrics: FieldLabelMetrics = .classic) -> [FieldLabel] {
        let w = Double(f.width), h = Double(f.height)
        // Three fine buckets: 15 seconds, about one turn of an agentic loop.
        let lag = 3
        let fine = s.fine
        guard fine.count > lag + 4 else { return [] }
        let flow = fine.map { FieldScale.normalise(Double($0.tokens.fresh), quiet: 160, loud: 30_000) }

        // Every other bucket: at one point per five seconds the figure tangles into a scribble.
        var pts: [CGPoint] = []
        for i in stride(from: lag, to: flow.count, by: 2) {
            let now = flow[i], before = flow[i - lag]
            guard now > 0 || before > 0 else { continue }
            pts.append(CGPoint(x: w * (0.08 + 0.84 * now), y: h * (0.92 - 0.84 * before)))
        }
        let n = pts.count
        guard n > 3 else { return [] }
        for i in 1..<n {
            let age = Double(i) / Double(n)
            f.curve([pts[max(0, i - 2)], pts[i - 1], pts[i], pts[min(n - 1, i + 1)]],
                    2.4 * m.energy * (0.15 + 0.85 * age), .beam, samples: 5)
        }
        if let last = pts.last { f.dot(last.x, last.y, 22 * m.energy) }
        return [FieldLabel(text: "T-15S", x: 2, y: 2, faint: true),
                FieldLabel(text: "NOW", x: f.width - metrics.width("NOW") - 2,
                           y: f.height - metrics.height - 2, faint: true)]
    }
}

/// Lays labels out next to the nodes they name without letting any two collide, or a label
/// cover a node (SPEC 2.9, WEB).
///
/// Each label tries its texts longest first, and each text tries four sides of its node, starting
/// with the one facing away from the hub: that is where the edges are not. A label that fits
/// nowhere is left out rather than printed over something else.
struct LabelPlacer {
    struct Box: Equatable {
        var x: Int, y: Int, w: Int, h: Int
        func intersects(_ o: Box) -> Bool {
            x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h
        }
        func touches(circle c: CGPoint, radius r: Double) -> Bool {
            let nx = min(max(c.x, Double(x)), Double(x + w - 1))
            let ny = min(max(c.y, Double(y)), Double(y + h - 1))
            let dx = c.x - nx, dy = c.y - ny
            return dx * dx + dy * dy <= r * r
        }
    }

    enum Side: CaseIterable { case below, above, right, left }

    let width: Int
    let height: Int
    let metrics: FieldLabelMetrics
    /// The knock-out patch of every label placed so far (ink box plus one pixel all round).
    private(set) var placed: [Box] = []
    private(set) var obstacles: [(centre: CGPoint, radius: Double)] = []

    init(width: Int, height: Int, metrics: FieldLabelMetrics) {
        self.width = width
        self.height = height
        self.metrics = metrics
    }

    mutating func avoid(_ centre: CGPoint, radius: Double) {
        obstacles.append((centre, radius))
    }

    /// The sides to try, nearest the direction away from `hub` first.
    static func sides(for p: CGPoint, from hub: CGPoint) -> [Side] {
        let dx = p.x - hub.x, dy = p.y - hub.y
        let vertical: Side = dy < 0 ? .above : .below
        let horizontal: Side = dx < 0 ? .left : .right
        func opposite(_ s: Side) -> Side {
            switch s { case .below: return .above; case .above: return .below
                       case .left: return .right; case .right: return .left }
        }
        // Names read best centred under or over their node, so the vertical sides go first
        // unless the node sits well out to the side of the hub.
        if abs(dx) > abs(dy) * 2.5 {
            return [horizontal, vertical, opposite(vertical), opposite(horizontal)]
        }
        return [vertical, horizontal, opposite(horizontal), opposite(vertical)]
    }

    /// Where a text of this ink size would go on one side of a node, kept inside the field.
    func box(side: Side, textWidth tw: Int, near p: CGPoint, radius r: Double) -> Box {
        let th = metrics.height
        let gap = 2.0
        var x: Int, y: Int
        switch side {
        case .below:
            x = Int((p.x - Double(tw) / 2).rounded()); y = Int((p.y + r + gap + 1).rounded())
        case .above:
            x = Int((p.x - Double(tw) / 2).rounded()); y = Int((p.y - r - gap - 1).rounded()) - th
        case .right:
            x = Int((p.x + r + gap + 2).rounded()); y = Int((p.y - Double(th) / 2).rounded())
        case .left:
            x = Int((p.x - r - gap - 2).rounded()) - tw; y = Int((p.y - Double(th) / 2).rounded())
        }
        x = min(max(1, x), max(1, width - tw - 1))
        y = min(max(1, y), max(1, height - th - 1))
        return Box(x: x, y: y, w: tw, h: th)
    }

    /// Whether an ink box can go here: its patch clear of every placed patch and every node.
    func fits(_ ink: Box) -> Bool {
        let patch = Box(x: ink.x - 1, y: ink.y - 1, w: ink.w + 2, h: ink.h + 2)
        guard patch.x >= 0, patch.y >= 0, patch.x + patch.w <= width, patch.y + patch.h <= height
        else { return false }
        if placed.contains(where: { $0.intersects(patch) }) { return false }
        return !obstacles.contains { patch.touches(circle: $0.centre, radius: $0.radius + 1) }
    }

    /// Place the first text that fits on any side of the node, or nothing.
    mutating func place(_ texts: [String], near p: CGPoint, radius r: Double, from hub: CGPoint,
                        faint: Bool) -> FieldLabel? {
        let order = LabelPlacer.sides(for: p, from: hub)
        for text in texts {
            let tw = metrics.width(text)
            guard tw > 0, tw + 2 <= width else { continue }
            for side in order {
                let ink = box(side: side, textWidth: tw, near: p, radius: r)
                guard fits(ink) else { continue }
                placed.append(Box(x: ink.x - 1, y: ink.y - 1, w: ink.w + 2, h: ink.h + 2))
                return FieldLabel(text: text, x: ink.x, y: ink.y, faint: faint)
            }
        }
        return nil
    }
}
