import Foundation
import UsageModel

/// The five configurations the Token Flow window can be in (SPEC 2.9).
///
/// They are not five charts of five things: they are five geometries for the same field, and the
/// modulators in `FieldModulators` ride on top of whichever one is up.
public enum FieldMode: String, CaseIterable, Codable {
    /// The bipolar trace: output above the axis, input and cache writes below, cache reads behind.
    case scope
    /// The ledger: the fresh token classes stacked over a range, with the pace line.
    case strata
    /// The connectome: sessions and models around a hub, pulsing as work arrives.
    case web
    /// The polar wall: the limit window as a ring, with the burn trace inside it.
    case orbit
    /// The phase figure: how hard a turn worked against how much of it was new text.
    case phase

    public var title: String {
        switch self {
        case .scope: return "Scope"
        case .strata: return "Strata"
        case .web: return "Web"
        case .orbit: return "Orbit"
        case .phase: return "Phase"
        }
    }

    /// Shown in the window's bottom readout, in the classic 5x6 font's charset.
    public var label: String { title.uppercased() }

    public var next: FieldMode {
        let all = FieldMode.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// How far back STRATA looks. The other configurations have a fixed span.
public enum FieldSpan: String, CaseIterable, Codable {
    case minutes    // 60 x 1 min
    case hours      // 24 x 1 h
    case days       // 10 days

    public var title: String {
        switch self {
        case .minutes: return "Last hour"
        case .hours: return "Last day"
        case .days: return "Last 10 days"
        }
    }

    public var label: String {
        switch self {
        case .minutes: return "1H"
        case .hours: return "24H"
        case .days: return "10D"
        }
    }

    public var next: FieldSpan {
        let all = FieldSpan.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    public var previous: FieldSpan {
        let all = FieldSpan.allCases
        return all[(all.firstIndex(of: self)! + all.count - 1) % all.count]
    }

    func buckets(_ s: UsageSnapshot) -> [UsageBucket] {
        switch self {
        case .minutes: return s.minutes
        case .hours: return s.hours
        case .days: return s.days
        }
    }
}

/// What the state of the account does to the field, whichever configuration is drawing it
/// (SPEC 2.9). Every one of these is a pure function of the snapshot.
public struct FieldModulators: Equatable {
    /// The tightest plan limit, 0...1. Biases the palette hot and closes the wall in.
    public var pressure: Double
    /// Beam gain: burn rate, faded down by how long it has been since anything happened.
    public var energy: Double
    /// Phosphor time constant in seconds. Bursty work keeps a long tail so spikes linger;
    /// steady work gets a short one and reads as a clean ribbon.
    public var persistence: Double
    /// Strength of the cache-read echo layer.
    public var echo: Double
    /// Position in the hero limit's window, 0...1: the timebase every configuration shares.
    public var phase: Double
    /// One beam per active session.
    public var beams: Int
    /// True when the account is in the severity band the service calls critical.
    public var critical: Bool

    public init(snapshot s: UsageSnapshot, now: Date) {
        let worst = s.limits.map { $0.percent }.max() ?? 0
        pressure = min(1, max(0, worst / 100))
        critical = s.limits.contains { $0.severity.lowercased() == "critical" } || pressure >= 0.9

        let idle = s.lastEventAt.map { now.timeIntervalSince($0) } ?? 3_600
        let live = idle > 600 ? 0.18 : (idle > 120 ? 0.5 : 1.0)
        // Fresh tokens exclude cache reads, so the numbers are smaller than they look in a
        // transcript: 60k a minute is already a hard-working agentic loop.
        let burn = min(1, max(0, s.burnTokensPerMin / 60_000))
        energy = (0.25 + 0.75 * burn) * live

        persistence = 0.35 + FieldModulators.burstiness(s) * 1.9
        echo = 0.55
        phase = s.limit(.session)?.elapsedFraction(at: now)
            ?? s.limits.first?.elapsedFraction(at: now) ?? 0
        beams = max(1, min(4, s.activeSessionCount))
    }

    /// How long the tail should be for one configuration.
    ///
    /// Persistence is a property of a *beam*: it means the display is still showing where the beam
    /// has been. That earns its keep in SCOPE, WEB and ORBIT, where something genuinely moves
    /// between frames - the trace scrolls, pulses expand, the arm sweeps. STRATA and PHASE are
    /// plots: they stand still until the data rolls, and then they jump. A long tail there does
    /// not draw motion, it smears the jump, so they get a short one and read crisp.
    public func tail(for mode: FieldMode) -> Double {
        switch mode {
        case .strata, .phase: return 0.2
        case .scope, .web, .orbit: return persistence
        }
    }

    /// 0 = a steady stream of work, 1 = bursts separated by silence. Measured as the share of the
    /// recent fine buckets that are empty, which is exactly what makes work feel bursty.
    static func burstiness(_ s: UsageSnapshot) -> Double {
        let recent = s.fine.suffix(48)
        guard !recent.isEmpty else { return 0.5 }
        let quiet = recent.filter { $0.costUSD <= 0 }.count
        let share = Double(quiet) / Double(recent.count)
        // All-quiet is idleness, not burstiness; the peak is around half empty.
        return min(1, max(0, 1 - abs(share - 0.5) * 2))
    }
}

/// Per-session flow, recovered by diffing successive snapshots.
///
/// `UsageModel` is frozen and carries only per-session totals, so there is no per-session time
/// series to read (SPEC 2.9). The controller feeds every published snapshot through here and the
/// connectome asks it how live each node is.
public final class SessionFlowTracker {

    private struct Entry {
        var tokens: Double
        var lastDelta: Double
        var lastChangeAt: Date
    }

    private var entries: [String: Entry] = [:]
    /// Deltas older than this stop counting as flow.
    private let window: TimeInterval = 90

    public init() {}

    public func ingest(_ snapshot: UsageSnapshot, now: Date) {
        var seen = Set<String>()
        for row in snapshot.sessionsToday {
            seen.insert(row.id)
            let tokens = Double(row.tokens.total)
            if var e = entries[row.id] {
                let delta = tokens - e.tokens
                if delta > 0 {
                    e.lastDelta = delta
                    e.lastChangeAt = now
                }
                e.tokens = tokens
                entries[row.id] = e
            } else {
                entries[row.id] = Entry(tokens: tokens, lastDelta: 0, lastChangeAt: now)
            }
        }
        entries = entries.filter { seen.contains($0.key) }
    }

    /// 0...1 for one session: how much has moved through it lately, faded out over `window`.
    public func flow(_ id: String, now: Date) -> Double {
        guard let e = entries[id], e.lastDelta > 0 else { return 0 }
        let age = now.timeIntervalSince(e.lastChangeAt)
        guard age < window else { return 0 }
        let fade = 1 - age / window
        // 400k tokens in one publish is a big turn.
        return min(1, e.lastDelta / 400_000) * fade
    }

    public func reset() { entries.removeAll() }
}

/// Picks the configuration when the window is on AUTO (SPEC 2.9).
///
/// Hysteresis matters more than cleverness here: a display that flips between two geometries every
/// time a number crosses a threshold is unreadable, so a choice has to hold for `dwell` seconds
/// before another one can take over, and only a critical limit may cut in early.
public struct FieldDirector {

    /// How long a different answer has to hold before the display acts on it.
    public static let dwell: TimeInterval = 24

    public private(set) var current: FieldMode
    /// The configuration the state has been asking for, and since when. A *debounce*, not a rate
    /// limit: one poll where a second session momentarily looks live must not flip a steady
    /// display, so the new answer has to keep being the answer for `dwell` before it wins.
    private var pending: FieldMode?
    private var pendingSince: Date

    public init(start: FieldMode = .scope, now: Date = Date()) {
        current = start
        pendingSince = now
    }

    /// The configuration the state asks for, before the debounce.
    public static func preferred(_ s: UsageSnapshot, mods: FieldModulators, now: Date) -> FieldMode {
        // A wall you are about to hit outranks everything else.
        if mods.critical { return .orbit }
        if let session = s.limit(.session), let resets = session.resetsAt,
           resets.timeIntervalSince(now) < 600 { return .orbit }
        let idle = s.lastEventAt.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        if idle > 600 { return s.sessionsToday.count > 1 ? .strata : .orbit }
        if s.activeSessionCount >= 2 { return .web }
        return .scope
    }

    /// Advance the director and return what to draw.
    public mutating func resolve(_ s: UsageSnapshot, mods: FieldModulators, now: Date) -> FieldMode {
        let want = FieldDirector.preferred(s, mods: mods, now: now)
        // A critical limit cuts in at once; it is the one state worth interrupting for.
        if mods.critical, want == .orbit {
            current = want
            pending = nil
            return current
        }
        guard want != current else {
            pending = nil
            return current
        }
        if pending != want {
            pending = want
            pendingSince = now
        }
        if now.timeIntervalSince(pendingSince) >= FieldDirector.dwell {
            current = want
            pending = nil
        }
        return current
    }
}

/// Shared scaling. Cost per bucket is not a useful axis here - a five second bucket costs cents -
/// so the field is scaled in tokens, logarithmically, like the faceplate visualiser.
public enum FieldScale {
    public static func normalise(_ v: Double, quiet: Double, loud: Double) -> Double {
        guard v > 0, loud > quiet, quiet > 0 else { return 0 }
        return min(1, max(0, log10(1 + v / quiet) / log10(1 + loud / quiet)))
    }
}
