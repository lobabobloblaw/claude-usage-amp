import Foundation
import UsageModel

/// Pure time formatting for the big digits, the marquee and the hover readings (SPEC 2.1/2.5).
/// Everything here is deterministic given a clock and a calendar, so `--selftest` can pin it down.
public enum TimeFormatting {

    /// What the four big digits show.
    public enum DigitMode: String, Codable {
        /// Time until the hero limit resets, with a minus sign (Winamp's "remaining" mode).
        case remaining
        /// Time since the hero limit's window opened.
        case elapsed
    }

    /// The four digit cells plus whether the minus sign is lit.
    public struct DigitReadout: Equatable {
        /// Exactly 4 characters from "0"..."9" or " ".
        public var glyphs: String
        public var minus: Bool
        /// True when we fell back to the wall clock because no limit was available.
        public var isWallClock: Bool

        public init(glyphs: String, minus: Bool, isWallClock: Bool = false) {
            self.glyphs = glyphs
            self.minus = minus
            self.isWallClock = isWallClock
        }
    }

    /// `HH:MM` when the interval is at least an hour, `MM:SS` below that. Returns the 4 digits.
    /// Values beyond 99 hours clamp; negatives clamp to zero.
    public static func digits(forInterval seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded(.down)))
        if total >= 3600 {
            let h = min(99, total / 3600)
            let m = (total % 3600) / 60
            return pad2(h) + pad2(m)
        }
        return pad2(total / 60) + pad2(total % 60)
    }

    public static func pad2(_ v: Int) -> String {
        let c = min(99, max(0, v))
        return c < 10 ? "0\(c)" : "\(c)"
    }

    /// The main window's time display.
    public static func readout(hero: LimitGauge?, mode: DigitMode, now: Date,
                               calendar: Calendar = .current) -> DigitReadout {
        guard let hero, let resets = hero.resetsAt else {
            // No limits at all: wall clock HH:MM, no minus (SPEC 2.1).
            let comps = calendar.dateComponents([.hour, .minute], from: now)
            return DigitReadout(glyphs: pad2(comps.hour ?? 0) + pad2(comps.minute ?? 0),
                                minus: false, isWallClock: true)
        }
        let remaining = max(0, resets.timeIntervalSince(now))
        switch mode {
        case .remaining:
            return DigitReadout(glyphs: digits(forInterval: remaining), minus: true)
        case .elapsed:
            let window = hero.windowSeconds ?? remaining
            return DigitReadout(glyphs: digits(forInterval: max(0, window - remaining)), minus: false)
        }
    }

    /// `2H47M`, `47M`, `12M`, `0M` - the compact form used in marquee and hover readings.
    public static func compactDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)H\(m)M" }
        if m > 0 { return "\(m)M" }
        return "\(total)S"
    }

    /// Local-time reset wording for the marquee (SPEC 2.1): `6:50 PM` today, `SAT 1 PM` later.
    /// Minutes are dropped on the day form only when they are zero, so nothing is ever a lie.
    public static func resetWording(_ reset: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let reset else { return "UNKNOWN" }
        var cal = calendar
        cal.locale = Locale(identifier: "en_US_POSIX")
        let comps = cal.dateComponents([.hour, .minute, .weekday], from: reset)
        let hour24 = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let ampm = hour24 < 12 ? "AM" : "PM"
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }

        if cal.isDate(reset, inSameDayAs: now) {
            return "\(hour12):\(pad2(minute)) \(ampm)"
        }
        let names = ["", "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        let day = names[min(max(comps.weekday ?? 1, 1), 7)]
        if minute == 0 { return "\(day) \(hour12) \(ampm)" }
        return "\(day) \(hour12):\(pad2(minute)) \(ampm)"
    }

    /// `12:34` wall clock, used by the shade strip when nothing else is known.
    public static func wallClock(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return pad2(c.hour ?? 0) + ":" + pad2(c.minute ?? 0)
    }
}

/// Number wording shared by the marquee, the playlist and the hover readings. Upper case,
/// classic-font charset only.
public enum NumberFormatting {

    /// 1234 -> "1.2K", 1_250_000 -> "1.2M", 12 -> "12".
    public static func abbreviated(_ value: Double) -> String {
        let v = abs(value)
        func trim(_ x: Double, _ suffix: String) -> String {
            let r = (x * 10).rounded() / 10
            if r >= 100 || r == r.rounded() { return "\(Int(r.rounded()))\(suffix)" }
            return String(format: "%.1f%@", r, suffix)
        }
        if v >= 1_000_000_000 { return trim(value / 1_000_000_000, "B") }
        if v >= 1_000_000 { return trim(value / 1_000_000, "M") }
        if v >= 1_000 { return trim(value / 1_000, "K") }
        return "\(Int(value.rounded()))"
    }

    /// `$12.40`, `$1.2K` above four figures.
    public static func money(_ usd: Double) -> String {
        if abs(usd) >= 10_000 { return "$" + abbreviated(usd) }
        if abs(usd) >= 100 { return String(format: "$%.0f", usd) }
        return String(format: "$%.2f", usd)
    }

    /// Percent with no decimals, clamped to 0...999.
    public static func percent(_ pct: Double) -> String {
        "\(Int(min(999, max(0, pct.rounded()))))%"
    }
}
