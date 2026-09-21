import Foundation
import UsageModel

public enum VisualizerMode: String, CaseIterable, Codable {
    case spectrum
    case oscilloscope
    case off

    public var next: VisualizerMode {
        switch self {
        case .spectrum: return .oscilloscope
        case .oscilloscope: return .off
        case .off: return .spectrum
        }
    }

    public var title: String {
        switch self {
        case .spectrum: return "Spectrum"
        case .oscilloscope: return "Oscilloscope"
        case .off: return "Off"
        }
    }
}

/// Token flow -> 19 spectrum bars (or a 76-column scope) for the 76 x 5 s fine buckets (SPEC 2.1).
///
/// The model is pure arithmetic plus one easing integrator, so the animated view and the
/// deterministic `--snapshot` render share it: `settled()` is exactly what `advance()` converges to.
public final class VisualizerModel {

    /// 19 bars x 4 px (3 px bar + 1 px gap) fills the 76 px well.
    public static let barCount = 19
    public static let barPitch = 4
    public static let barWidth = 3
    /// Fine buckets per bar.
    public static let bucketsPerBar = UsageSnapshot.fineBucketCount / barCount   // 4

    /// Log-ish scaling reference points, in USD per 5 s bucket.
    static let quietCost = 0.01
    static let loudCost = 2.0

    public private(set) var bars: [Double]
    public private(set) var peaks: [Double]
    /// 0 while stopped: the whole display decays to nothing (SPEC 2.1, stop button).
    public var gain: Double = 1

    private var shimmerSeed: UInt64 = 0x2545_F491_4F6C_DD1D

    public init() {
        bars = Array(repeating: 0, count: VisualizerModel.barCount)
        peaks = Array(repeating: 0, count: VisualizerModel.barCount)
    }

    // MARK: - Pure targets

    /// 0...1 height for one mean bucket cost.
    public static func normalize(cost: Double) -> Double {
        guard cost > 0 else { return 0 }
        let v = log10(1 + cost / quietCost) / log10(1 + loudCost / quietCost)
        return min(1, max(0, v))
    }

    /// Bar targets, oldest at index 0 (left) and newest at 18 (right).
    public static func targets(_ snapshot: UsageSnapshot) -> [Double] {
        let fine = snapshot.fine
        var out = [Double](repeating: 0, count: barCount)
        guard !fine.isEmpty else { return out }
        // Align to the end of the array so the newest bucket is always in the last bar.
        let offset = max(0, fine.count - barCount * bucketsPerBar)
        for j in 0..<barCount {
            var sum = 0.0
            var n = 0
            for k in 0..<bucketsPerBar {
                let i = offset + j * bucketsPerBar + k
                guard i >= 0, i < fine.count else { continue }
                sum += fine[i].costUSD
                n += 1
            }
            out[j] = n > 0 ? normalize(cost: sum / Double(n)) : 0
        }
        return out
    }

    /// Bars whose buckets include the current 10 seconds; these get the live shimmer.
    public static func hotBars(_ snapshot: UsageSnapshot, now: Date) -> Set<Int> {
        let fine = snapshot.fine
        guard !fine.isEmpty else { return [] }
        let cutoff = now.addingTimeInterval(-10)
        let offset = max(0, fine.count - barCount * bucketsPerBar)
        var out: Set<Int> = []
        for j in 0..<barCount {
            for k in 0..<bucketsPerBar {
                let i = offset + j * bucketsPerBar + k
                guard i >= 0, i < fine.count else { continue }
                if fine[i].start.addingTimeInterval(fine[i].duration) >= cutoff { out.insert(j); break }
            }
        }
        return out
    }

    /// Oscilloscope samples, one per fine bucket, -1...1 around the centre line.
    public static func scope(_ snapshot: UsageSnapshot) -> [Double] {
        let fine = snapshot.fine
        var out = [Double](repeating: 0, count: UsageSnapshot.fineBucketCount)
        guard !fine.isEmpty else { return out }
        let offset = max(0, fine.count - UsageSnapshot.fineBucketCount)
        for i in 0..<out.count {
            let k = offset + i
            guard k < fine.count else { break }
            let amp = normalize(cost: fine[k].costUSD)
            // A deterministic waveform whose excursion follows cost: a scope, not a bar chart.
            out[i] = amp * sin(Double(i) * 0.83)
        }
        return out
    }

    /// The settled state `advance()` converges to: bars at their targets with peak caps 2 rows
    /// above (SPEC 3.1). This is what `--snapshot` renders, so goldens are reproducible.
    public static func settled(_ snapshot: UsageSnapshot, rows: Int = 16) -> (bars: [Double], peaks: [Double]) {
        let t = targets(snapshot)
        let step = 1.0 / Double(max(1, rows))
        let peaks = t.map { $0 > 0 ? min(1, $0 + 2 * step) : 0 }
        return (t, peaks)
    }

    // MARK: - Animation

    /// Advance the eased bars and the falling caps by `dt` seconds.
    /// Fast attack, slow decay, caps that fall at a constant rate (classic Winamp feel).
    public func advance(snapshot: UsageSnapshot, now: Date, dt: TimeInterval, rows: Int = 16) {
        let t = VisualizerModel.targets(snapshot)
        let hot = VisualizerModel.hotBars(snapshot, now: now)
        let attack = 1 - pow(0.02, min(0.2, dt) * 8)     // ~fast
        let decay = 1 - pow(0.5, min(0.2, dt) * 3)       // ~slow
        let capFall = 0.85 * dt
        let step = 1.0 / Double(max(1, rows))

        for i in 0..<VisualizerModel.barCount {
            var target = t[i] * gain
            if gain > 0, hot.contains(i), target > 0 {
                // A small per-frame shimmer so live work visibly dances.
                target = min(1, target + (nextShimmer() - 0.35) * 2.2 * step)
            }
            let k = target > bars[i] ? attack : decay
            bars[i] += (target - bars[i]) * k
            if bars[i] < 0.0005 { bars[i] = 0 }
            let floorPeak = bars[i] > 0 ? bars[i] + 2 * step : 0
            peaks[i] = max(floorPeak, peaks[i] - capFall)
            if peaks[i] <= bars[i] { peaks[i] = floorPeak }
            peaks[i] = min(1, peaks[i])
        }
    }

    /// Jump straight to the settled state (used when the window first appears).
    public func settle(snapshot: UsageSnapshot, rows: Int = 16) {
        let s = VisualizerModel.settled(snapshot, rows: rows)
        bars = s.bars
        peaks = s.peaks
    }

    public func silence() {
        bars = Array(repeating: 0, count: VisualizerModel.barCount)
        peaks = Array(repeating: 0, count: VisualizerModel.barCount)
    }

    /// xorshift: cheap, self-contained, and never touches the global RNG.
    private func nextShimmer() -> Double {
        shimmerSeed ^= shimmerSeed << 13
        shimmerSeed ^= shimmerSeed >> 7
        shimmerSeed ^= shimmerSeed << 17
        return Double(shimmerSeed % 1_000) / 1_000
    }
}
