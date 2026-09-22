import Foundation

// The contract between the data layer (UsageCore) and the UI (TokenampKit).
// Everything here is a plain value type; nothing in this target performs I/O.

/// Token counts as reported in the `usage` object of an API response.
public struct TokenCounts: Sendable, Equatable, Codable {
    public var input: Int
    public var output: Int
    /// cache_creation_input_tokens (5 minute + 1 hour writes combined)
    public var cacheWrite: Int
    /// cache_read_input_tokens
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public static let zero = TokenCounts()

    /// Every token that crossed the wire, cache reads included.
    public var total: Int { input + output + cacheWrite + cacheRead }
    /// Tokens that were actually processed fresh: everything except cache reads.
    /// This is what "burn rate" is measured in, because cache reads dwarf the rest and cost ~nothing.
    public var fresh: Int { input + output + cacheWrite }

    public static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input, output: a.output + b.output,
                    cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
    }

    public static func += (a: inout TokenCounts, b: TokenCounts) { a = a + b }
}

/// Usage aggregated over one span of time.
public struct UsageBucket: Sendable, Equatable, Codable {
    public var start: Date
    public var duration: TimeInterval
    public var tokens: TokenCounts
    /// API-list-price equivalent. On a subscription plan this is an estimate of value, not a bill.
    public var costUSD: Double
    public var messages: Int

    public init(start: Date, duration: TimeInterval, tokens: TokenCounts = .zero, costUSD: Double = 0, messages: Int = 0) {
        self.start = start
        self.duration = duration
        self.tokens = tokens
        self.costUSD = costUSD
        self.messages = messages
    }
}

/// One plan limit as the account reports it (the rows of Claude Code's /usage screen).
public struct LimitGauge: Sendable, Equatable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case session        // rolling 5 hour window
        case weeklyAll      // 7 day, all models
        case weeklyScoped   // 7 day, one model family
        case other
    }

    /// Stable key, e.g. "session", "weekly_all", "weekly_scoped:Fable".
    public var id: String
    public var kind: Kind
    /// Marquee-ready title, upper case, classic-font charset only. e.g. "SESSION (5H)", "WEEK - ALL MODELS", "WEEK - FABLE".
    public var title: String
    /// 0...100
    public var percent: Double
    public var resetsAt: Date?
    /// Length of the limit window if known (18000 for session, 604800 for weekly).
    public var windowSeconds: TimeInterval?
    /// "normal", "warning", "critical" ... as reported; unknown strings pass through.
    public var severity: String
    /// True for the limit the service currently marks as the binding one.
    public var isActive: Bool

    public init(id: String, kind: Kind, title: String, percent: Double, resetsAt: Date?,
                windowSeconds: TimeInterval?, severity: String = "normal", isActive: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.percent = percent
        self.resetsAt = resetsAt
        self.windowSeconds = windowSeconds
        self.severity = severity
        self.isActive = isActive
    }

    /// Fraction (0...1) of the window that has elapsed at `now`, when both reset time and window are known.
    public func elapsedFraction(at now: Date) -> Double? {
        guard let resetsAt, let windowSeconds, windowSeconds > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(1, max(0, 1 - remaining / windowSeconds))
    }
}

/// One Claude Code session (a transcript file plus its subagent transcripts) seen today.
public struct SessionRow: Sendable, Equatable, Codable, Identifiable {
    public var id: String               // session UUID
    public var project: String          // short display name, e.g. "code/tokenamp"
    public var cwd: String?             // full working directory if known
    public var model: String            // short display name of the dominant model, e.g. "FABLE 5.1"
    public var tokens: TokenCounts
    public var costUSD: Double
    public var messages: Int
    public var firstActivity: Date
    public var lastActivity: Date
    /// Activity within the last 2 minutes.
    public var isActive: Bool

    public init(id: String, project: String, cwd: String?, model: String, tokens: TokenCounts, costUSD: Double,
                messages: Int, firstActivity: Date, lastActivity: Date, isActive: Bool) {
        self.id = id
        self.project = project
        self.cwd = cwd
        self.model = model
        self.tokens = tokens
        self.costUSD = costUSD
        self.messages = messages
        self.firstActivity = firstActivity
        self.lastActivity = lastActivity
        self.isActive = isActive
    }
}

public enum LiveStatus: Sendable, Equatable, Codable {
    case disabled                    // user turned the live source off
    case neverFetched
    case ok(lastFetch: Date)
    case authExpired                 // token missing/expired; Claude Code will refresh it next time it runs
    case rateLimited(retryAt: Date)
    case error(String)

    public var isOK: Bool { if case .ok = self { return true } else { return false } }
}

public struct LocalStatus: Sendable, Equatable, Codable {
    public var isScanning: Bool
    public var filesDone: Int
    public var filesTotal: Int

    public init(isScanning: Bool = false, filesDone: Int = 0, filesTotal: Int = 0) {
        self.isScanning = isScanning
        self.filesDone = filesDone
        self.filesTotal = filesTotal
    }
}

/// Everything the UI needs, computed for one instant. Arrays are ordered oldest -> newest and the
/// last element always covers "now" (so it is partial).
public struct UsageSnapshot: Sendable, Equatable, Codable {
    public static let fineBucketSeconds: TimeInterval = 5
    public static let fineBucketCount = 76          // one per visualizer pixel column; 76 * 5 s = 6 min 20 s
    public static let minuteBucketCount = 60
    public static let hourBucketCount = 24
    public static let dayBucketCount = 10

    public var generatedAt: Date
    /// e.g. "MAX 20X", "PRO", "" when unknown. Upper case, classic-font charset.
    public var planName: String
    /// Session first, then weekly-all, then scoped limits. Empty when the live source is unavailable.
    public var limits: [LimitGauge]
    public var liveStatus: LiveStatus
    public var localStatus: LocalStatus

    public var fine: [UsageBucket]      // fineBucketCount x 5 s, aligned to multiples of 5 s since epoch
    public var minutes: [UsageBucket]   // 60 x 60 s, aligned to the minute
    public var hours: [UsageBucket]     // 24 x 3600 s, aligned to the hour
    public var days: [UsageBucket]      // 10 local calendar days
    public var today: UsageBucket       // local calendar day so far
    public var sessionsToday: [SessionRow]  // most recent activity first

    /// Mean `fresh` tokens per minute over the last 5 minutes.
    public var burnTokensPerMin: Double
    /// Cost rate extrapolated from the last 5 minutes.
    public var burnUSDPerHour: Double
    public var activeSessionCount: Int
    public var lastEventAt: Date?

    public init(generatedAt: Date, planName: String = "", limits: [LimitGauge] = [],
                liveStatus: LiveStatus = .neverFetched, localStatus: LocalStatus = LocalStatus(),
                fine: [UsageBucket] = [], minutes: [UsageBucket] = [], hours: [UsageBucket] = [],
                days: [UsageBucket] = [], today: UsageBucket? = nil, sessionsToday: [SessionRow] = [],
                burnTokensPerMin: Double = 0, burnUSDPerHour: Double = 0, activeSessionCount: Int = 0,
                lastEventAt: Date? = nil) {
        self.generatedAt = generatedAt
        self.planName = planName
        self.limits = limits
        self.liveStatus = liveStatus
        self.localStatus = localStatus
        self.fine = fine
        self.minutes = minutes
        self.hours = hours
        self.days = days
        self.today = today ?? UsageBucket(start: Calendar.current.startOfDay(for: generatedAt), duration: 86400)
        self.sessionsToday = sessionsToday
        self.burnTokensPerMin = burnTokensPerMin
        self.burnUSDPerHour = burnUSDPerHour
        self.activeSessionCount = activeSessionCount
        self.lastEventAt = lastEventAt
    }

    public static func empty(at date: Date = Date()) -> UsageSnapshot { UsageSnapshot(generatedAt: date) }

    public func limit(_ kind: LimitGauge.Kind) -> LimitGauge? { limits.first { $0.kind == kind } }
}
