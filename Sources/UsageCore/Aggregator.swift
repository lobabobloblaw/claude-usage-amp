import Foundation
import UsageModel

/// Folds deduplicated events into the exact array shapes `UsageSnapshot` documents.
///
/// All arrays are oldest -> newest, always full length, and the last element always covers `now`
/// (so it is partial). Fine/minute/hour grids are aligned to epoch multiples, matching
/// `DemoUsageProvider`; days are local calendar days.
final class Aggregator {

    private let pricing: PricingResolver
    private var displayNameCache: [String: String] = [:]
    private var projectNameCache: [String: String] = [:]
    /// Local calendar days follow the machine's current time zone. `autoupdatingCurrent` tracks a
    /// time-zone change (travel, a manual change in System Settings) without a relaunch, where a
    /// `Calendar.current` captured once would keep the zone the process started in.
    private let calendar = Calendar.autoupdatingCurrent

    init(pricing: PricingResolver) {
        self.pricing = pricing
    }

    // MARK: - Snapshot

    func snapshot(events: [UsageEvent],
                  now: Date,
                  planName: String,
                  limits: [LimitGauge],
                  liveStatus: LiveStatus,
                  localStatus: LocalStatus) -> UsageSnapshot {

        let nowEpoch = now.timeIntervalSince1970

        // --- grids -------------------------------------------------------------------------
        let fineSeconds = UsageSnapshot.fineBucketSeconds
        let fineCount = UsageSnapshot.fineBucketCount
        let fineLast = (nowEpoch / fineSeconds).rounded(.down)
        let fineFirst = fineLast - Double(fineCount - 1)

        let minuteCount = UsageSnapshot.minuteBucketCount
        let minuteLast = (nowEpoch / 60).rounded(.down)
        let minuteFirst = minuteLast - Double(minuteCount - 1)

        let hourCount = UsageSnapshot.hourBucketCount
        let hourLast = (nowEpoch / 3600).rounded(.down)
        let hourFirst = hourLast - Double(hourCount - 1)

        let dayCount = UsageSnapshot.dayBucketCount
        let startOfToday = calendar.startOfDay(for: now)
        var dayStarts: [Double] = []
        dayStarts.reserveCapacity(dayCount + 1)
        for k in stride(from: dayCount - 1, through: 0, by: -1) {
            let d = calendar.date(byAdding: .day, value: -k, to: startOfToday) ?? startOfToday.addingTimeInterval(Double(-k) * 86_400)
            dayStarts.append(d.timeIntervalSince1970)
        }
        let endOfToday = (calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)).timeIntervalSince1970
        dayStarts.append(endOfToday)

        var fineAcc = [Accumulator](repeating: Accumulator(), count: fineCount)
        var minuteAcc = [Accumulator](repeating: Accumulator(), count: minuteCount)
        var hourAcc = [Accumulator](repeating: Accumulator(), count: hourCount)
        var dayAcc = [Accumulator](repeating: Accumulator(), count: dayCount)

        // --- session rows ------------------------------------------------------------------
        var sessionAcc: [String: SessionAccumulator] = [:]
        let todayStartEpoch = dayStarts[dayCount - 1]
        let burnWindowStart = nowEpoch - 300
        let activeSince = nowEpoch - 120
        var burnTokens = 0
        var burnCost = 0.0
        var lastEvent: Double = 0

        // `Int(Double)` traps on NaN, on infinity and outside Int's range, and an event timestamp
        // is data from another process. Every bounds test therefore happens in Double, where a NaN
        // simply fails both comparisons, and the conversion only runs on a value known to be in
        // `0 ..< count`.
        @inline(__always) func slot(_ t: Double, _ step: Double, _ first: Double, _ count: Int) -> Int? {
            let raw = (t / step).rounded(.down) - first
            guard raw >= 0, raw < Double(count) else { return nil }
            return Int(raw)
        }
        /// A clock that is ahead by a few seconds is ordinary; one that is ahead by years is not,
        /// and letting it set `lastEventAt` would freeze "last event" at a negative age for ever.
        let futureCutoff = nowEpoch + 120

        // Events are sorted, so the walk starts at the oldest bucket boundary we care about.
        let scanFrom = min(dayStarts[0], fineFirst * fineSeconds, minuteFirst * 60, hourFirst * 3600)
        var i = lowerBound(events, timestamp: scanFrom)
        while i < events.count {
            let e = events[i]
            i += 1
            let t = e.timestamp
            if t > lastEvent && t <= futureCutoff { lastEvent = t }
            let cost = pricing.cost(model: e.model, input: e.input, output: e.output,
                                    cacheWrite5m: e.cacheWrite5m, cacheWrite1h: e.cacheWrite1h,
                                    cacheRead: e.cacheRead, fast: e.fast)
            let counts = e.counts

            if let fi = slot(t, fineSeconds, fineFirst, fineCount) { fineAcc[fi].add(counts, cost) }
            if let mi = slot(t, 60, minuteFirst, minuteCount) { minuteAcc[mi].add(counts, cost) }
            if let hi = slot(t, 3600, hourFirst, hourCount) { hourAcc[hi].add(counts, cost) }
            if t >= dayStarts[0] && t < dayStarts[dayCount] {
                var di = dayCount - 1
                while di > 0 && t < dayStarts[di] { di -= 1 }
                dayAcc[di].add(counts, cost)
            }
            if t >= burnWindowStart && t <= nowEpoch + 60 {
                burnTokens += counts.input + counts.output + counts.cacheWrite
                burnCost += cost
            }
            // Same bounds as the `today` bucket, so the session rows and the day total can never
            // disagree about what "today" contains.
            if t >= todayStartEpoch && t < dayStarts[dayCount] {
                let key = e.sessionID.isEmpty ? "unknown" : e.sessionID
                if sessionAcc[key] == nil {
                    sessionAcc[key] = SessionAccumulator(id: key, cwd: e.cwd, first: t, last: t)
                }
                sessionAcc[key]!.add(event: e, counts: counts, cost: cost)
            }
        }

        // --- arrays ------------------------------------------------------------------------
        var fine: [UsageBucket] = []
        fine.reserveCapacity(fineCount)
        for k in 0..<fineCount {
            fine.append(fineAcc[k].bucket(start: (fineFirst + Double(k)) * fineSeconds, duration: fineSeconds))
        }
        var minutes: [UsageBucket] = []
        minutes.reserveCapacity(minuteCount)
        for k in 0..<minuteCount {
            minutes.append(minuteAcc[k].bucket(start: (minuteFirst + Double(k)) * 60, duration: 60))
        }
        var hours: [UsageBucket] = []
        hours.reserveCapacity(hourCount)
        for k in 0..<hourCount {
            hours.append(hourAcc[k].bucket(start: (hourFirst + Double(k)) * 3600, duration: 3600))
        }
        var days: [UsageBucket] = []
        days.reserveCapacity(dayCount)
        for k in 0..<dayCount {
            days.append(dayAcc[k].bucket(start: dayStarts[k], duration: dayStarts[k + 1] - dayStarts[k]))
        }
        let today = days[dayCount - 1]

        // --- sessions ----------------------------------------------------------------------
        var rows: [SessionRow] = []
        rows.reserveCapacity(sessionAcc.count)
        for (_, s) in sessionAcc {
            rows.append(SessionRow(id: s.id,
                                   project: projectName(for: s.cwd, sessionID: s.id),
                                   cwd: s.cwd.isEmpty ? nil : s.cwd,
                                   model: displayName(s.dominantModel()),
                                   tokens: s.counts.asPublic,
                                   costUSD: s.cost,
                                   messages: s.messages,
                                   firstActivity: Date(timeIntervalSince1970: s.first),
                                   lastActivity: Date(timeIntervalSince1970: s.last),
                                   isActive: s.last >= activeSince))
        }
        rows.sort { $0.lastActivity == $1.lastActivity ? $0.id < $1.id : $0.lastActivity > $1.lastActivity }
        let activeCount = rows.reduce(0) { $0 + ($1.isActive ? 1 : 0) }

        return UsageSnapshot(generatedAt: now,
                             planName: planName,
                             limits: limits,
                             liveStatus: liveStatus,
                             localStatus: localStatus,
                             fine: fine,
                             minutes: minutes,
                             hours: hours,
                             days: days,
                             today: today,
                             sessionsToday: rows,
                             burnTokensPerMin: Double(burnTokens) / 5,
                             burnUSDPerHour: burnCost * 12,
                             activeSessionCount: activeCount,
                             lastEventAt: lastEvent > 0 ? Date(timeIntervalSince1970: lastEvent) : nil)
    }

    // MARK: - Helpers

    private func lowerBound(_ events: [UsageEvent], timestamp: Double) -> Int {
        var lo = 0, hi = events.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if events[mid].timestamp < timestamp { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func displayName(_ model: String) -> String {
        if let hit = displayNameCache[model] { return hit }
        let n = ModelDisplayName.of(model)
        displayNameCache[model] = n
        return n
    }

    /// `/Users/me/code/tokenamp` -> `code/tokenamp`.
    func projectName(for cwd: String, sessionID: String) -> String {
        if cwd.isEmpty { return sessionID.isEmpty ? "unknown" : String(sessionID.prefix(8)) }
        if let hit = projectNameCache[cwd] { return hit }
        let home = NSHomeDirectory()
        var path = cwd
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        var relative = path
        if path == home {
            relative = "~"
        } else if path.hasPrefix(home + "/") {
            relative = String(path.dropFirst(home.count + 1))
        }
        // UUID directories (scratch workspaces, session folders) carry no meaning for a human
        // reading a playlist row, so they are dropped before the last two components are taken.
        var comps = relative.split(separator: "/").map(String.init)
        let meaningful = comps.filter { !Aggregator.looksLikeUUID($0) }
        if !meaningful.isEmpty { comps = meaningful }
        var name: String
        if comps.isEmpty {
            name = relative
        } else if comps.count == 1 {
            name = comps[0]
        } else {
            name = comps[comps.count - 2] + "/" + comps[comps.count - 1]
        }
        if name.count > 40, let last = comps.last { name = last }
        projectNameCache[cwd] = name
        return name
    }

    static func looksLikeUUID(_ s: String) -> Bool {
        guard s.count == 36 else { return false }
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 5,
              parts[0].count == 8, parts[1].count == 4, parts[2].count == 4,
              parts[3].count == 4, parts[4].count == 12 else { return false }
        return parts.allSatisfy { $0.allSatisfy { $0.isHexDigit } }
    }
}

// MARK: - Accumulators

private struct Accumulator {
    var counts = TokenCountsLite()
    var cost = 0.0
    var messages = 0

    @inline(__always) mutating func add(_ c: TokenCountsLite, _ usd: Double) {
        counts += c
        cost += usd
        messages += 1
    }

    func bucket(start: Double, duration: TimeInterval) -> UsageBucket {
        UsageBucket(start: Date(timeIntervalSince1970: start), duration: duration,
                    tokens: counts.asPublic, costUSD: cost, messages: messages)
    }
}

private struct SessionAccumulator {
    let id: String
    var cwd: String
    var first: Double
    var last: Double
    var counts = TokenCountsLite()
    var cost = 0.0
    var messages = 0
    /// model id -> fresh tokens, used to pick the session's dominant model.
    var models: [String: Int] = [:]

    @inline(__always) mutating func add(event e: UsageEvent, counts c: TokenCountsLite, cost usd: Double) {
        if e.timestamp < first { first = e.timestamp }
        if e.timestamp > last { last = e.timestamp }
        if cwd.isEmpty && !e.cwd.isEmpty { cwd = e.cwd }
        counts += c
        cost += usd
        messages += 1
        models[e.model, default: 0] += c.input + c.output + c.cacheWrite
    }

    func dominantModel() -> String {
        var best = ""
        var bestValue = -1
        for (m, v) in models where v > bestValue || (v == bestValue && m < best) {
            best = m
            bestValue = v
        }
        return best
    }
}
