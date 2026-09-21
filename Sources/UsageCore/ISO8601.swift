import Foundation

/// Hand-rolled ISO-8601 reader. `ISO8601DateFormatter` is far too slow for tens of thousands of
/// transcript lines and refuses 6-digit fractional seconds in some configurations; this accepts
/// `YYYY-MM-DDTHH:MM:SS`, any number of fractional digits, and `Z`, `+HH:MM`, `+HHMM`, `+HH` or
/// nothing (treated as UTC, which is what Claude Code writes). A truncated offset (`+0`) is rejected.
public enum ISO8601 {

    /// Epoch seconds, or nil when the text is not a timestamp.
    public static func epochSeconds(_ bytes: UnsafeRawBufferPointer) -> Double? {
        let n = bytes.count
        guard n >= 19 else { return nil }
        @inline(__always) func digit(_ i: Int) -> Int? {
            let c = bytes[i]
            return (c >= 0x30 && c <= 0x39) ? Int(c - 0x30) : nil
        }
        /// `len` digits starting at `i`, or nil when they are not all there. The bounds check is what
        /// makes a short offset such as `+05` or `+0` at the very end of the text safe to probe.
        @inline(__always) func num(_ i: Int, _ len: Int) -> Int? {
            guard i >= 0, len >= 0, i + len <= n else { return nil }
            var v = 0
            for k in 0..<len {
                guard let d = digit(i + k) else { return nil }
                v = v * 10 + d
            }
            return v
        }
        guard let year = num(0, 4), bytes[4] == 0x2D,
              let month = num(5, 2), bytes[7] == 0x2D,
              let day = num(8, 2),
              bytes[10] == 0x54 || bytes[10] == 0x20 || bytes[10] == 0x74,
              let hour = num(11, 2), bytes[13] == 0x3A,
              let minute = num(14, 2), bytes[16] == 0x3A,
              let second = num(17, 2) else { return nil }

        var i = 19
        var fraction = 0.0
        if i < n, bytes[i] == 0x2E {
            i += 1
            var scale = 0.1
            while i < n, let d = digit(i) {
                fraction += Double(d) * scale
                scale /= 10
                i += 1
            }
        }
        var offset = 0
        if i < n {
            let c = bytes[i]
            if c == 0x5A || c == 0x7A {           // Z
                i += 1
            } else if c == 0x2B || c == 0x2D {    // + / -
                let sign = (c == 0x2D) ? -1 : 1
                i += 1
                guard let oh = num(i, 2) else { return nil }
                i += 2
                if i < n, bytes[i] == 0x3A { i += 1 }
                let om = num(i, 2) ?? 0
                offset = sign * (oh * 3600 + om * 60)
            }
        }
        let days = daysFromCivil(year: year, month: month, day: day)
        let secs = Double(days) * 86_400 + Double(hour * 3600 + minute * 60 + second - offset)
        return secs + fraction
    }

    public static func epochSeconds(_ text: String) -> Double? {
        var s = text
        return s.withUTF8 { buf in epochSeconds(UnsafeRawBufferPointer(buf)) }
    }

    public static func date(_ text: String) -> Date? {
        guard let s = epochSeconds(text) else { return nil }
        return Date(timeIntervalSince1970: s)
    }

    /// Howard Hinnant's days-from-civil; valid for the whole proleptic Gregorian calendar.
    @inline(__always)
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        var y = year
        y -= month <= 2 ? 1 : 0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
