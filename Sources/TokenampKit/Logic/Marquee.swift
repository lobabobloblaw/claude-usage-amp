import Foundation
import UsageModel

/// Composition of the scrolling marquee and of the hover readings that temporarily replace it
/// (SPEC 2.1 and 2.5). Everything returned here is already restricted to the classic font's
/// charset, upper case, so `BitmapFont.sanitize` is a no-op on it.
public enum Marquee {

    public static let separator = " *** "

    /// The looping headline. Sections are joined by ` *** ` and the whole thing is followed by one
    /// more separator so the loop reads continuously.
    public static func compose(snapshot: UsageSnapshot, heroIndex: Int, isPaused: Bool, isStopped: Bool,
                               now: Date, calendar: Calendar = .current) -> String {
        var parts: [String] = []

        if let hero = HeroTrack.hero(in: snapshot, index: heroIndex) {
            let n = HeroTrack.trackNumber(index: heroIndex, count: snapshot.limits.count)
            let resets = TimeFormatting.resetWording(hero.resetsAt, now: now, calendar: calendar)
            parts.append("\(n). \(hero.title) - \(NumberFormatting.percent(hero.percent)) USED - RESETS \(resets)")
        } else {
            parts.append("TOKENAMP - NO PLAN LIMITS AVAILABLE")
        }

        if let s = HeroTrack.sessionPercent(snapshot) {
            parts.append("SESSION \(NumberFormatting.percent(s))")
        }
        if let w = HeroTrack.weeklyPercent(snapshot) {
            parts.append("WEEK \(NumberFormatting.percent(w))")
        }
        if !snapshot.planName.isEmpty { parts.append(snapshot.planName) }

        parts.append("BURN \(NumberFormatting.abbreviated(snapshot.burnTokensPerMin)) TOK/MIN")
        parts.append("TODAY \(NumberFormatting.abbreviated(Double(snapshot.today.tokens.total))) / "
                     + NumberFormatting.money(snapshot.today.costUSD))

        if let status = statusPhrase(snapshot: snapshot, isPaused: isPaused, isStopped: isStopped) {
            parts.append(status)
        }

        return BitmapFont.sanitize(parts.joined(separator: separator) + separator)
    }

    /// Anything the user needs to know about the data itself. nil when everything is healthy.
    public static func statusPhrase(snapshot: UsageSnapshot, isPaused: Bool, isStopped: Bool) -> String? {
        if isStopped { return "STOPPED" }
        if isPaused { return "PAUSED" }
        if snapshot.localStatus.isScanning {
            return "SCANNING \(snapshot.localStatus.filesDone)/\(snapshot.localStatus.filesTotal)"
        }
        switch snapshot.liveStatus {
        case .authExpired: return "LIVE: AUTH EXPIRED - OPEN CLAUDE CODE"
        case .rateLimited: return "LIVE: RATE LIMITED"
        case .error(let e): return "LIVE: " + BitmapFont.sanitize(String(e.prefix(40)))
        case .neverFetched: return "LIVE: WAITING"
        case .disabled: return "LIVE DATA OFF"
        case .ok: return nil
        }
    }

    // MARK: - Scrolling

    /// One glyph to draw in the marquee strip: character plus its x offset inside the strip.
    public struct Glyph {
        public let character: Character
        public let x: Int
    }

    /// The glyphs visible in a `width`-pixel window of `text`, scrolled by `offset` pixels.
    /// Text wraps around, so the marquee loops forever without a seam.
    public static func visibleGlyphs(text: String, offset: Int, width: Int) -> [Glyph] {
        let chars = Array(text)
        guard !chars.isEmpty, width > 0 else { return [] }
        let unit = chars.count * BitmapFont.glyphWidth
        let off = ((offset % unit) + unit) % unit
        var out: [Glyph] = []
        var x = -(off % BitmapFont.glyphWidth)
        var index = off / BitmapFont.glyphWidth
        while x < width {
            out.append(Glyph(character: chars[index % chars.count], x: x))
            x += BitmapFont.glyphWidth
            index += 1
        }
        return out
    }

    /// Total scroll length in pixels; the offset wraps at this value.
    public static func scrollWidth(_ text: String) -> Int {
        max(1, text.count * BitmapFont.glyphWidth)
    }

    // MARK: - Hover readings (SPEC 2.5)

    public static func volumeReading(_ snapshot: UsageSnapshot, now: Date) -> String {
        guard let g = snapshot.limit(.session) else { return "SESSION: NO DATA" }
        let left = g.resetsAt.map { "RESETS IN " + TimeFormatting.compactDuration($0.timeIntervalSince(now)) } ?? "RESET UNKNOWN"
        return BitmapFont.sanitize("SESSION: \(NumberFormatting.percent(g.percent)) USED - \(left)")
    }

    public static func balanceReading(_ snapshot: UsageSnapshot, now: Date, calendar: Calendar = .current) -> String {
        guard let g = snapshot.limit(.weeklyAll) else { return "WEEK (ALL): NO DATA" }
        let when = TimeFormatting.resetWording(g.resetsAt, now: now, calendar: calendar)
        return BitmapFont.sanitize("WEEK (ALL): \(NumberFormatting.percent(g.percent)) USED - RESETS \(when)")
    }

    public static func posbarReading(_ snapshot: UsageSnapshot, heroIndex: Int, now: Date) -> String {
        guard let hero = HeroTrack.hero(in: snapshot, index: heroIndex), let resets = hero.resetsAt else {
            return "NO HERO LIMIT"
        }
        let left = max(0, resets.timeIntervalSince(now))
        let elapsed = max(0, (hero.windowSeconds ?? left) - left)
        return BitmapFont.sanitize("\(hero.title): \(TimeFormatting.compactDuration(elapsed)) ELAPSED / "
                                   + "\(TimeFormatting.compactDuration(left)) LEFT")
    }

    public static func burnReading(_ snapshot: UsageSnapshot) -> String {
        BitmapFont.sanitize("BURN: \(NumberFormatting.abbreviated(snapshot.burnTokensPerMin)) TOK/MIN  "
                            + NumberFormatting.money(snapshot.burnUSDPerHour) + "/HR")
    }

    public static func activeSessionsReading(_ snapshot: UsageSnapshot) -> String {
        let n = snapshot.activeSessionCount
        return n == 1 ? "1 ACTIVE SESSION" : "\(n) ACTIVE SESSIONS"
    }

    public static func sourcesReading(_ snapshot: UsageSnapshot) -> String {
        var live: String
        switch snapshot.liveStatus {
        case .ok(let at):
            live = "LIVE OK (" + TimeFormatting.compactDuration(Date().timeIntervalSince(at)) + " AGO)"
        case .disabled: live = "LIVE OFF"
        case .neverFetched: live = "LIVE WAITING"
        case .authExpired: live = "LIVE AUTH EXPIRED"
        case .rateLimited: live = "LIVE RATE LIMITED"
        case .error(let e): live = "LIVE ERROR: " + String(e.prefix(24))
        }
        let local = snapshot.localStatus.isScanning
            ? "LOCAL SCANNING \(snapshot.localStatus.filesDone)/\(snapshot.localStatus.filesTotal)"
            : "LOCAL \(snapshot.localStatus.filesTotal) FILES"
        return BitmapFont.sanitize(local + " - " + live)
    }

    public static func visualizerReading() -> String { "TOKEN FLOW - LAST 6 MIN" }

    /// `T-3H: 1.24M TOK  $4.10` (SPEC 2.3).
    public static func eqBandReading(label: String, tokens: Double, cost: Double) -> String {
        BitmapFont.sanitize("\(label): \(NumberFormatting.abbreviated(tokens)) TOK  "
                            + NumberFormatting.money(cost))
    }

    public static func eqPreampReading(_ snapshot: UsageSnapshot) -> String {
        guard let g = snapshot.limit(.weeklyScoped) ?? snapshot.limit(.weeklyAll) else { return "WEEK: NO DATA" }
        return BitmapFont.sanitize("\(g.title): \(NumberFormatting.percent(g.percent)) USED")
    }
}
