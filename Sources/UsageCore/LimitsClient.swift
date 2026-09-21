import Foundation
import UsageModel

/// Result of one poll of the account's plan limits.
enum LiveFetchOutcome {
    case success(planName: String, limits: [LimitGauge])
    case authExpired
    /// `retryAt` is set only when the server said so through `Retry-After`. Without it the caller
    /// backs off exponentially (SPEC 4.3), which it cannot do if a default is invented here.
    case rateLimited(retryAt: Date?)
    case failure(String)
}

/// When the next live poll may happen after an outcome. Pure, so the schedule is testable without
/// a network (SPEC 4.3: honour `Retry-After`, else exponential backoff to 15 min).
enum LivePollPolicy {

    /// Ceiling of our own exponential backoff (429 without `Retry-After`, network/HTTP failures).
    static let maxBackoff: TimeInterval = 900
    /// Longest `Retry-After` honoured. The server may legitimately ask for more than our own
    /// backoff ceiling; a value beyond this is treated as this.
    static let maxRetryAfter: TimeInterval = 6 * 3600
    /// No two polls closer together than this, `refreshNow()` and post-reset polls included.
    static let minSpacing: TimeInterval = 10

    static func schedule(outcome: LiveFetchOutcome, now: Date,
                         previousBackoff: TimeInterval) -> (nextAllowedAt: Date, backoff: TimeInterval) {
        switch outcome {
        case .success, .authExpired:
            // An expired token is refreshed by Claude Code itself, so keep asking on the normal
            // schedule rather than backing away from it.
            return (.distantPast, 0)
        case .rateLimited(let retryAt):
            let grown = min(maxBackoff, max(60, previousBackoff * 2))
            if let retryAt { return (min(retryAt, now.addingTimeInterval(maxRetryAfter)), grown) }
            return (now.addingTimeInterval(grown), grown)
        case .failure:
            let grown = min(maxBackoff, max(30, previousBackoff * 2))
            return (now.addingTimeInterval(grown), grown)
        }
    }

    /// Whether a poll may start now.
    ///
    /// - `force` (`refreshNow()`, start-up, re-enabling): at most one per `minSpacing`, and never
    ///   inside a server-requested 429 wait. Our own backoff is overridden.
    /// - Otherwise the normal cadence: `interval` while there was local activity in the last
    ///   5 min, else 300 s — or sooner once `resetPollAt` (set just after a limit reset) is due.
    ///   Either way `nextAllowedAt` (429 `Retry-After` or backoff) is respected.
    static func shouldPoll(force: Bool, now: Date, lastPollAt: Date, nextAllowedAt: Date,
                           rateLimited: Bool, recentActivity: Bool, interval: TimeInterval,
                           resetPollAt: Date?, minSpacing: TimeInterval = LivePollPolicy.minSpacing) -> Bool {
        let sinceLast = now.timeIntervalSince(lastPollAt)
        guard sinceLast >= minSpacing else { return false }
        if force { return !(rateLimited && now < nextAllowedAt) }
        guard now >= nextAllowedAt else { return false }
        if let resetPollAt, now >= resetPollAt { return true }
        let cadence = recentActivity ? min(900, max(30, interval)) : 300
        return sinceLast >= cadence
    }

    /// Delay between a limit reset being noticed and the poll that fetches the new window: a few
    /// seconds, so the service has rolled over, jittered so many clients do not poll in lockstep.
    static func resetPollDelay(unit: Double = Double.random(in: 0...1)) -> TimeInterval {
        2 + 4 * min(1, max(0, unit))
    }
}

/// What a limit looks like once its reset time has passed and no fresher reading has arrived.
enum LimitRollover {

    /// A limit whose `resetsAt` is not in the future is a new, empty window: it is published at
    /// 0 % (severity `normal`) with `resetsAt` moved forward by whole windows until it is in the
    /// future. Without a known window the reset time becomes unknown. Limits still inside their
    /// window are returned unchanged. `rolled` is true when anything changed.
    static func roll(_ gauges: [LimitGauge], now: Date) -> (gauges: [LimitGauge], rolled: Bool) {
        var rolled = false
        let out = gauges.map { g -> LimitGauge in
            guard let resetsAt = g.resetsAt, resetsAt <= now else { return g }
            rolled = true
            var next = g
            next.percent = 0
            next.severity = "normal"
            if let window = g.windowSeconds, window.isFinite, window > 0 {
                let windows = ((now.timeIntervalSince(resetsAt)) / window).rounded(.down) + 1
                next.resetsAt = resetsAt.addingTimeInterval(windows * window)
                // Floating point at the boundary: never publish a reset that is already due.
                if let r = next.resetsAt, r <= now { next.resetsAt = r.addingTimeInterval(window) }
            } else {
                next.resetsAt = nil
            }
            return next
        }
        return (out, rolled)
    }
}

/// The account credential, as read from the keychain (or the fallback file).
///
/// This type exists so the access token has one well-defined lifetime: it is read immediately
/// before a request, put into one `Authorization` header for `api.anthropic.com`, and dropped.
/// It is never logged, never written to disk, never placed in a snapshot, and never sent anywhere
/// else. Nothing in this file prints it, and `description` deliberately hides it.
struct ClaudeCredential: CustomStringConvertible {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?
    let rateLimitTier: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    var description: String { "ClaudeCredential(token: <redacted>, expires: \(expiresAt.map { "\($0)" } ?? "unknown"))" }
}

/// Reads the credential read-only. Never refreshes it, never writes to the keychain.
enum CredentialReader {

    static let keychainService = "Claude Code-credentials"

    static func read() -> ClaudeCredential? {
        if let data = readFromKeychain(), let c = parse(data) { return c }
        if let data = try? Data(contentsOf: TokenampPaths.credentialsFallbackURL), let c = parse(data) { return c }
        return nil
    }

    private static func readFromKeychain() -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    static func parse(_ data: Data) -> ClaudeCredential? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let oauth = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        var expires: Date?
        if let ms = JSONNumber.double(oauth["expiresAt"]), ms > 0 {
            expires = Date(timeIntervalSince1970: ms > 1e11 ? ms / 1000 : ms)
        }
        return ClaudeCredential(accessToken: token,
                                expiresAt: expires,
                                subscriptionType: oauth["subscriptionType"] as? String,
                                rateLimitTier: oauth["rateLimitTier"] as? String)
    }
}

/// Refuses to follow any redirect.
///
/// `URLSession` carries the headers of the original request — including `Authorization` — into the
/// request it builds for a redirect. A `301` from anywhere in front of the endpoint (a captive
/// portal, an intercepting proxy, a compromised DNS answer) would therefore hand the account's
/// bearer token to whatever host the redirect names. SPEC 4.3 says the token goes to
/// `api.anthropic.com` and nowhere else, so the redirect is simply not followed and the 3xx is
/// reported as an ordinary HTTP failure.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The live plan-limit client (SPEC 4.3).
final class LimitsClient {

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let allowedHost = "api.anthropic.com"

    private let session: URLSession
    private let redirectDelegate = NoRedirectDelegate()
    /// Reading the keychain means running `/usr/bin/security`, which is a fork+exec and can block
    /// for a noticeable time (longer still if the keychain is locked). It must not happen on the
    /// caller's queue: that is the scan queue, and a stalled scan queue is a stalled clock.
    private let workQueue = DispatchQueue(label: "app.tokenamp.limits", qos: .utility)

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpAdditionalHeaders = [:]
        session = URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
    }

    deinit { session.finishTasksAndInvalidate() }

    /// One poll. The credential is re-read for every poll, because Claude Code rotates it.
    func fetch(completion: @escaping (LiveFetchOutcome) -> Void) {
        workQueue.async { [weak self] in
            guard let self else { return completion(.failure("stopped")) }
            self.performFetch(completion: completion)
        }
    }

    private func performFetch(completion: @escaping (LiveFetchOutcome) -> Void) {
        guard let credential = CredentialReader.read() else {
            completion(.authExpired)
            return
        }
        let planName = LimitsClient.planName(tier: credential.rateLimitTier, subscription: credential.subscriptionType)
        if credential.isExpired {
            completion(.authExpired)
            return
        }
        // Belt and braces: the endpoint is a compile-time constant, but the token is only ever
        // attached to a request whose host has been checked here as well.
        guard LimitsClient.endpoint.scheme == "https", LimitsClient.endpoint.host == LimitsClient.allowedHost else {
            completion(.failure("bad endpoint"))
            return
        }
        var request = URLRequest(url: LimitsClient.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer " + credential.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Tokenamp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpShouldHandleCookies = false

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(LimitsClient.shortError(error)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure("no response"))
                return
            }
            completion(LimitsClient.outcome(status: http.statusCode, body: data,
                                            retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After"),
                                            planName: planName, now: Date()))
        }.resume()
    }

    /// What one HTTP response means. Pure, so the status mapping is testable without a network.
    static func outcome(status: Int, body: Data?, retryAfterHeader: String?, planName: String, now: Date) -> LiveFetchOutcome {
        switch status {
        case 200:
            guard let body, let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
                return .failure("bad json")
            }
            return .success(planName: planName, limits: parseLimits(root))
        case 401:
            return .authExpired
        case 403:
            // Forbidden is not an expired token (that is 401, and Claude Code fixes it by itself):
            // it does not go away on its own, so it is reported as an error and backs off like one,
            // instead of reading "auth expired" for ever while being retried every minute.
            return .failure("http 403 forbidden")
        case 429:
            // Only a usable `Retry-After` produces a date; otherwise the caller backs off.
            return .rateLimited(retryAt: retryAfter(retryAfterHeader, now: now))
        default:
            return .failure("http \(status)")
        }
    }

    /// `Retry-After` as a date: delta-seconds (`120`) or an HTTP-date (`Wed, 21 Oct 2026 07:28:00
    /// GMT`), clamped to 1 s … `LivePollPolicy.maxRetryAfter` from `now`. nil when absent or unusable.
    static func retryAfter(_ value: String?, now: Date) -> Date? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        var seconds: TimeInterval?
        if let d = Double(raw), d.isFinite {
            seconds = d
        } else if let date = httpDateFormatter.date(from: raw) {
            seconds = date.timeIntervalSince(now)
        }
        guard let s = seconds else { return nil }
        return now.addingTimeInterval(min(max(s, 1), LivePollPolicy.maxRetryAfter))
    }

    /// IMF-fixdate (RFC 9110), the only HTTP-date form a current server sends.
    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f
    }()

    private static func shortError(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return "offline"
        case NSURLErrorTimedOut: return "timeout"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "dns"
        default: return "net \(ns.code)"
        }
    }

    // MARK: - Plan name

    /// `default_claude_max_20x` -> `MAX 20X`, `pro` -> `PRO`.
    static func planName(tier: String?, subscription: String?) -> String {
        let raw = (tier?.isEmpty == false ? tier! : (subscription ?? ""))
        guard !raw.isEmpty else { return "" }
        var s = raw.lowercased()
        for prefix in ["default_claude_", "default_", "claude_"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        s = s.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return sanitise(s.uppercased())
    }

    /// The classic bitmap font has a fixed charset; anything else becomes a space.
    static func sanitise(_ s: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .:()-'!_+\\/[]^&%,=$#@\"*?")
        return String(s.uppercased().map { allowed.contains($0) ? $0 : " " })
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Response parsing

    /// Prefers the `limits` array; falls back to the `five_hour` / `seven_day` / `seven_day_<x>`
    /// objects. Every field is optional and unknown keys are ignored (SPEC 4.3).
    static func parseLimits(_ root: [String: Any]) -> [LimitGauge] {
        var gauges: [LimitGauge] = []

        if let list = root["limits"] as? [Any], !list.isEmpty {
            for item in list {
                guard let d = item as? [String: Any] else { continue }
                let kindRaw = (d["kind"] as? String) ?? ""
                let group = (d["group"] as? String) ?? ""
                let kind = kindFor(kindRaw: kindRaw, group: group)
                // `percent` may be absent or null: every field of this response is optional. When it
                // is, the matching legacy object's `utilization` is the only reading there is, and
                // it must be taken whatever its value — a gauge stuck at 0 % because one key was
                // missing reads as "no usage", which is a lie the whole app is built on top of.
                let statedPercent = JSONNumber.double(d["percent"])
                var percent = statedPercent ?? 0
                let resets = (d["resets_at"] as? String).flatMap(ISO8601.date)
                let scopeName = scopeDisplayName(d["scope"])
                let window = windowSeconds(kind: kind, group: group)

                // A more precise utilisation from the legacy objects wins over the integer percent.
                if let refined = refinedPercent(root: root, kind: kind, coarse: statedPercent) { percent = refined }

                let id: String
                let title: String
                switch kind {
                case .session:
                    id = "session"; title = "SESSION (5H)"
                case .weeklyAll:
                    id = "weekly_all"; title = "WEEK - ALL MODELS"
                case .weeklyScoped:
                    let name = scopeName ?? "SCOPED"
                    id = "weekly_scoped:" + (scopeName ?? kindRaw)
                    title = "WEEK - " + sanitise(name)
                case .other:
                    id = kindRaw.isEmpty ? "other" : kindRaw
                    title = sanitise(kindRaw.replacingOccurrences(of: "_", with: " "))
                }
                gauges.append(LimitGauge(id: id, kind: kind, title: title,
                                         percent: clampPercent(percent), resetsAt: resets,
                                         windowSeconds: window,
                                         severity: (d["severity"] as? String) ?? "normal",
                                         isActive: (d["is_active"] as? Bool) ?? false))
            }
        } else {
            if let d = root["five_hour"] as? [String: Any] {
                gauges.append(LimitGauge(id: "session", kind: .session, title: "SESSION (5H)",
                                         percent: clampPercent(JSONNumber.double(d["utilization"]) ?? 0),
                                         resetsAt: (d["resets_at"] as? String).flatMap(ISO8601.date),
                                         windowSeconds: 18_000,
                                         severity: (d["severity"] as? String) ?? "normal",
                                         isActive: true))
            }
            if let d = root["seven_day"] as? [String: Any] {
                gauges.append(LimitGauge(id: "weekly_all", kind: .weeklyAll, title: "WEEK - ALL MODELS",
                                         percent: clampPercent(JSONNumber.double(d["utilization"]) ?? 0),
                                         resetsAt: (d["resets_at"] as? String).flatMap(ISO8601.date),
                                         windowSeconds: 604_800,
                                         severity: (d["severity"] as? String) ?? "normal",
                                         isActive: false))
            }
            for key in root.keys.sorted() where key.hasPrefix("seven_day_") {
                guard let d = root[key] as? [String: Any] else { continue }
                let name = scopeDisplayName(d["scope"]) ?? String(key.dropFirst("seven_day_".count))
                gauges.append(LimitGauge(id: "weekly_scoped:" + name, kind: .weeklyScoped,
                                         title: "WEEK - " + sanitise(name),
                                         percent: clampPercent(JSONNumber.double(d["utilization"]) ?? 0),
                                         resetsAt: (d["resets_at"] as? String).flatMap(ISO8601.date),
                                         windowSeconds: 604_800,
                                         severity: (d["severity"] as? String) ?? "normal",
                                         isActive: false))
            }
        }

        return order(gauges)
    }

    static func order(_ gauges: [LimitGauge]) -> [LimitGauge] {
        func rank(_ k: LimitGauge.Kind) -> Int {
            switch k {
            case .session: return 0
            case .weeklyAll: return 1
            case .weeklyScoped: return 2
            case .other: return 3
            }
        }
        return gauges.sorted {
            rank($0.kind) == rank($1.kind) ? $0.title < $1.title : rank($0.kind) < rank($1.kind)
        }
    }

    private static func kindFor(kindRaw: String, group: String) -> LimitGauge.Kind {
        switch kindRaw {
        case "session": return .session
        case "weekly_all": return .weeklyAll
        case "weekly_scoped": return .weeklyScoped
        default:
            if group == "session" { return .session }
            return .other
        }
    }

    private static func windowSeconds(kind: LimitGauge.Kind, group: String) -> TimeInterval? {
        switch kind {
        case .session: return 18_000
        case .weeklyAll, .weeklyScoped: return 604_800
        case .other:
            if group == "session" { return 18_000 }
            if group == "weekly" { return 604_800 }
            return nil
        }
    }

    private static func scopeDisplayName(_ any: Any?) -> String? {
        guard let scope = any as? [String: Any] else { return nil }
        if let model = scope["model"] as? [String: Any] {
            if let name = model["display_name"] as? String, !name.isEmpty { return name }
            if let id = model["id"] as? String, !id.isEmpty { return ModelDisplayName.of(id) }
        }
        if let name = scope["display_name"] as? String, !name.isEmpty { return name }
        return nil
    }

    /// `five_hour.utilization` / `seven_day.utilization` carry fractional precision that the
    /// integer `percent` in the `limits` array loses. With a `percent` to compare against they are
    /// used only when they clearly describe the same number; with no `percent` at all they are the
    /// reading.
    private static func refinedPercent(root: [String: Any], kind: LimitGauge.Kind, coarse: Double?) -> Double? {
        let key: String
        switch kind {
        case .session: key = "five_hour"
        case .weeklyAll: key = "seven_day"
        default: return nil
        }
        guard let d = root[key] as? [String: Any], let u = JSONNumber.double(d["utilization"]) else { return nil }
        guard let coarse else { return u }
        guard abs(u - coarse) <= 1.0, u != coarse else { return nil }
        return u
    }

    private static func clampPercent(_ p: Double) -> Double {
        guard p.isFinite else { return 0 }
        return min(100, max(0, p))
    }
}
