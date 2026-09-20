import Foundation

/// Deterministic synthetic data. Used by `--demo`, by offscreen snapshots (so renders are reproducible)
/// and by UI development before the real data layer is wired in.
///
/// All values are pure functions of the wall clock passed in, so a frozen clock gives identical output.
public final class DemoUsageProvider: UsageProvider {
    public private(set) var snapshot: UsageSnapshot
    public var onChange: ((UsageSnapshot) -> Void)?
    public var isPaused = false
    public var isLiveEnabled = true { didSet { publish() } }
    public var livePollInterval: TimeInterval = 60

    private var timer: Timer?
    /// When set, the provider reports this instant forever (reproducible snapshots).
    private let frozenClock: Date?

    public init(frozenAt: Date? = nil) {
        frozenClock = frozenAt
        snapshot = DemoUsageProvider.makeSnapshot(at: frozenAt ?? Date(), live: true)
    }

    /// 2026-09-20 21:37:12 UTC. A fixed instant for golden-image renders.
    public static let referenceDate = Date(timeIntervalSince1970: 1_789_940_232)

    public func start() {
        publish()
        guard timer == nil, frozenClock == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.publish()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refreshNow() { publish() }

    private func publish() {
        snapshot = DemoUsageProvider.makeSnapshot(at: frozenClock ?? Date(), live: isLiveEnabled)
        onChange?(snapshot)
    }

    // MARK: - Synthesis

    /// Cheap stable hash -> 0..<1
    private static func noise(_ a: Int, _ b: Int = 0) -> Double {
        var x = UInt64(bitPattern: Int64(a &* 73_856_093 ^ b &* 19_349_663)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 1_000_000) / 1_000_000
    }

    /// Activity envelope: bursts of work separated by idle gaps, like a real agentic session.
    private static func activity(atFineIndex i: Int) -> Double {
        let burst = noise(i / 9, 7)                       // ~45 s phrases
        guard burst > 0.28 else { return 0 }
        let swell = 0.55 + 0.45 * sin(Double(i) * 0.37)
        let grit = 0.35 + 0.65 * noise(i, 3)
        return max(0, burst * swell * grit)
    }

    private static func tokens(scale: Double) -> TokenCounts {
        TokenCounts(input: Int(scale * 180), output: Int(scale * 2_600),
                    cacheWrite: Int(scale * 9_500), cacheRead: Int(scale * 410_000))
    }

    /// Demo prices: a Fable-class mix.
    private static func cost(_ t: TokenCounts) -> Double {
        (Double(t.input) * 10 + Double(t.output) * 50 + Double(t.cacheWrite) * 20 + Double(t.cacheRead) * 1) / 1_000_000
    }

    private static func bucket(start: Date, duration: TimeInterval, scale: Double, messages: Int) -> UsageBucket {
        let t = tokens(scale: scale)
        return UsageBucket(start: start, duration: duration, tokens: t, costUSD: cost(t), messages: messages)
    }

    public static func makeSnapshot(at now: Date, live: Bool) -> UsageSnapshot {
        let epoch = now.timeIntervalSince1970
        let fineNow = Int(epoch / UsageSnapshot.fineBucketSeconds)

        var fine: [UsageBucket] = []
        for k in stride(from: UsageSnapshot.fineBucketCount - 1, through: 0, by: -1) {
            let i = fineNow - k
            let a = activity(atFineIndex: i)
            // the current bucket fills up as its 5 seconds elapse
            let fill = k == 0 ? (epoch / UsageSnapshot.fineBucketSeconds - Double(fineNow)) : 1
            fine.append(bucket(start: Date(timeIntervalSince1970: Double(i) * 5), duration: 5,
                               scale: a * fill, messages: a > 0 ? 1 : 0))
        }

        let minuteNow = Int(epoch / 60)
        var minutes: [UsageBucket] = []
        for k in stride(from: UsageSnapshot.minuteBucketCount - 1, through: 0, by: -1) {
            let m = minuteNow - k
            var s = 0.0
            for j in 0..<12 { s += activity(atFineIndex: m * 12 + j) }
            minutes.append(bucket(start: Date(timeIntervalSince1970: Double(m) * 60), duration: 60, scale: s, messages: Int(s * 2)))
        }

        let hourNow = Int(epoch / 3600)
        var hours: [UsageBucket] = []
        for k in stride(from: UsageSnapshot.hourBucketCount - 1, through: 0, by: -1) {
            let h = hourNow - k
            let hourOfDay = ((h % 24) + 24) % 24
            let awake = (hourOfDay >= 15 || hourOfDay <= 6) ? 1.0 : 0.08      // UTC hours ~ a US workday
            let s = awake * (120 + 520 * noise(h, 11))
            hours.append(bucket(start: Date(timeIntervalSince1970: Double(h) * 3600), duration: 3600, scale: s, messages: Int(s * 1.4)))
        }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        var days: [UsageBucket] = []
        for k in stride(from: UsageSnapshot.dayBucketCount - 1, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -k, to: startOfToday) ?? startOfToday
            let dayIndex = Int(d.timeIntervalSince1970 / 86400)
            let weekday = cal.component(.weekday, from: d)
            let weekend = (weekday == 1 || weekday == 7) ? 0.45 : 1.0
            let progress = k == 0 ? max(0.05, now.timeIntervalSince(startOfToday) / 86400) : 1
            let s = weekend * progress * (2_400 + 5_200 * noise(dayIndex, 5))
            days.append(bucket(start: d, duration: 86400, scale: s, messages: Int(s * 1.2)))
        }
        let today = days.last ?? UsageBucket(start: startOfToday, duration: 86400)

        let projects: [(String, String, Double)] = [
            ("fable5dot1/claude-usage-amp", "FABLE 5.1", 0.34),
            ("web/storefront-checkout", "OPUS 5", 0.22),
            ("infra/terraform-live", "SONNET 5", 0.16),
            ("research/eval-harness", "FABLE 5.1", 0.12),
            ("ios/field-notes", "OPUS 5", 0.07),
            ("scratch/regex-golf", "HAIKU 4.5", 0.04),
            ("docs/handbook", "SONNET 5", 0.03),
            ("dotfiles", "HAIKU 4.5", 0.02),
        ]
        var sessions: [SessionRow] = []
        for (n, p) in projects.enumerated() {
            let share = p.2
            let t = TokenCounts(input: Int(Double(today.tokens.input) * share), output: Int(Double(today.tokens.output) * share),
                                cacheWrite: Int(Double(today.tokens.cacheWrite) * share), cacheRead: Int(Double(today.tokens.cacheRead) * share))
            let last = now.addingTimeInterval(-Double(n * n) * 410 - (n == 0 ? 4 : 95))
            sessions.append(SessionRow(id: String(format: "demo-%02d", n), project: p.0, cwd: "/Users/demo/" + p.0, model: p.1,
                                       tokens: t, costUSD: today.costUSD * share, messages: Int(Double(today.messages) * share),
                                       firstActivity: last.addingTimeInterval(-3_600 * (1 + Double(n % 3))), lastActivity: last,
                                       isActive: n < 2))
        }

        let last5 = minutes.suffix(5)
        let burnTokens = Double(last5.reduce(0) { $0 + $1.tokens.fresh }) / 5
        let burnUSD = last5.reduce(0) { $0 + $1.costUSD } * 12

        // Session window: a 5 hour window that reset at 2 h 13 min before "now" on the reference clock,
        // and keeps rolling so the countdown is always alive.
        let sessionWindow: TimeInterval = 5 * 3600
        let phase = (epoch + 1_400).truncatingRemainder(dividingBy: sessionWindow)
        let sessionReset = now.addingTimeInterval(sessionWindow - phase)
        let sessionPct = min(99, 8 + 72 * phase / sessionWindow + 3 * sin(epoch / 40))
        let weekWindow: TimeInterval = 7 * 86400
        let weekPhase = (epoch + 200_000).truncatingRemainder(dividingBy: weekWindow)
        let weekReset = now.addingTimeInterval(weekWindow - weekPhase)

        let limits: [LimitGauge] = live ? [
            LimitGauge(id: "session", kind: .session, title: "SESSION (5H)", percent: sessionPct, resetsAt: sessionReset,
                       windowSeconds: sessionWindow, severity: sessionPct > 80 ? "warning" : "normal", isActive: true),
            LimitGauge(id: "weekly_all", kind: .weeklyAll, title: "WEEK - ALL MODELS", percent: 12 + 60 * weekPhase / weekWindow,
                       resetsAt: weekReset, windowSeconds: weekWindow),
            LimitGauge(id: "weekly_scoped:Fable", kind: .weeklyScoped, title: "WEEK - FABLE", percent: 9 + 78 * weekPhase / weekWindow,
                       resetsAt: weekReset, windowSeconds: weekWindow),
        ] : []

        return UsageSnapshot(generatedAt: now, planName: "MAX 20X", limits: limits,
                             liveStatus: live ? .ok(lastFetch: now.addingTimeInterval(-17)) : .disabled,
                             localStatus: LocalStatus(isScanning: false, filesDone: 323, filesTotal: 323),
                             fine: fine, minutes: minutes, hours: hours, days: days, today: today,
                             sessionsToday: sessions, burnTokensPerMin: burnTokens, burnUSDPerHour: burnUSD,
                             activeSessionCount: 2, lastEventAt: now.addingTimeInterval(-4))
    }
}
