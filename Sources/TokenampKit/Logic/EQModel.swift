import Foundation
import UsageModel

/// The "Usage Equalizer": 10 band sliders over the last 10 time buckets (SPEC 2.3).
public enum EQRange: String, CaseIterable, Codable {
    case hours
    case days
    case minutes

    public var title: String {
        switch self {
        case .hours: return "Last 10 hours"
        case .days: return "Last 10 days"
        case .minutes: return "Last 10 minutes"
        }
    }

    /// Marquee-friendly band label suffix: T-3H, T-3D, T-3M.
    var unitLetter: String {
        switch self {
        case .hours: return "H"
        case .days: return "D"
        case .minutes: return "M"
        }
    }

    public var next: EQRange {
        let all = EQRange.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

public enum EQMeasure: String, CaseIterable, Codable {
    case cost
    case outputTokens
    case allTokens

    public var title: String {
        switch self {
        case .cost: return "Cost (API-equivalent)"
        case .outputTokens: return "Output tokens"
        case .allTokens: return "All tokens"
        }
    }

    public var isMoney: Bool { self == .cost }
}

public struct EQBand {
    /// `T-9H` ... `NOW`
    public let label: String
    public let value: Double
    public let tokens: Double
    public let cost: Double
    /// 0...1 slider position after scaling.
    public let level: Double
}

public enum EQModel {

    public static let bandCount = 10

    /// Fixed-log scale endpoints (SPEC 2.3): $0.01...$100 for cost, 1k...100M for tokens.
    static func fixedLogRange(_ measure: EQMeasure) -> (lo: Double, hi: Double) {
        measure.isMoney ? (0.01, 100) : (1_000, 100_000_000)
    }

    static func buckets(_ snapshot: UsageSnapshot, range: EQRange) -> [UsageBucket] {
        let source: [UsageBucket]
        switch range {
        case .hours: source = snapshot.hours
        case .days: source = snapshot.days
        case .minutes: source = snapshot.minutes
        }
        guard source.count > bandCount else { return source }
        return Array(source.suffix(bandCount))
    }

    public static func value(_ bucket: UsageBucket, measure: EQMeasure) -> Double {
        switch measure {
        case .cost: return bucket.costUSD
        case .outputTokens: return Double(bucket.tokens.output)
        case .allTokens: return Double(bucket.tokens.total)
        }
    }

    /// The 10 bands, oldest left, newest right. `relative` = normalise to the max of the ten
    /// (ON lit, the default); otherwise use the fixed log scale.
    public static func bands(_ snapshot: UsageSnapshot, range: EQRange, measure: EQMeasure,
                             relative: Bool) -> [EQBand] {
        let bs = buckets(snapshot, range: range)
        guard !bs.isEmpty else { return [] }
        let values = bs.map { value($0, measure: measure) }
        let maxValue = values.max() ?? 0
        let fixed = fixedLogRange(measure)

        var out: [EQBand] = []
        for (i, b) in bs.enumerated() {
            let v = values[i]
            let level: Double
            if relative {
                level = maxValue > 0 ? min(1, max(0, v / maxValue)) : 0
            } else {
                level = logLevel(v, lo: fixed.lo, hi: fixed.hi)
            }
            let back = bs.count - 1 - i
            let label = back == 0 ? "NOW" : "T-\(back)\(range.unitLetter)"
            out.append(EQBand(label: label, value: v, tokens: Double(b.tokens.total),
                              cost: b.costUSD, level: level))
        }
        return out
    }

    /// 0...1 on a log scale between `lo` and `hi`; anything at or below `lo` is 0.
    public static func logLevel(_ v: Double, lo: Double, hi: Double) -> Double {
        guard v > lo, hi > lo else { return 0 }
        return min(1, max(0, log10(v / lo) / log10(hi / lo)))
    }

    /// Preamp slider: the model-scoped weekly limit % if one exists, else weekly-all (SPEC 2.3).
    public static func preampLevel(_ snapshot: UsageSnapshot) -> Double {
        guard let pct = HeroTrack.preampPercent(snapshot) else { return 0 }
        return min(1, max(0, pct / 100))
    }

    /// A smooth curve through the 10 band levels sampled at `width` x positions, 0...1.
    /// Catmull-Rom through the control points, clamped at the ends.
    public static func graphCurve(levels: [Double], width: Int) -> [Double] {
        guard width > 0 else { return [] }
        guard levels.count >= 2 else { return Array(repeating: levels.first ?? 0, count: width) }
        var out = [Double](repeating: 0, count: width)
        let n = levels.count
        for x in 0..<width {
            let t = Double(x) / Double(max(1, width - 1)) * Double(n - 1)
            let i = min(n - 2, max(0, Int(t)))
            let f = t - Double(i)
            let p0 = levels[max(0, i - 1)]
            let p1 = levels[i]
            let p2 = levels[i + 1]
            let p3 = levels[min(n - 1, i + 2)]
            let a = 2 * p1
            let b = p2 - p0
            let c = 2 * p0 - 5 * p1 + 4 * p2 - p3
            let d = -p0 + 3 * p1 - 3 * p2 + p3
            let v = 0.5 * (a + b * f + c * f * f + d * f * f * f)
            out[x] = min(1, max(0, v))
        }
        return out
    }
}
