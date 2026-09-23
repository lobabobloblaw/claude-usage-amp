import Foundation

/// The persistent scan cache: per-file byte offsets plus the usage events already extracted from
/// them, so a relaunch does not have to re-read 3.4 GB (SPEC 4.1).
///
/// The file is versioned and written atomically. Strings (session ids, model ids, cwds) are
/// interned into one table, which is what keeps the file a handful of megabytes rather than tens.
/// Reading is deliberately forgiving: anything unexpected makes the whole cache be ignored and the
/// scanner falls back to a cold scan.
enum ScanCache {

    /// 2 (amendment A5): every event row carries the fast-mode flag. A version 1 file cannot say
    /// which of its events were fast, so it is discarded and the next launch scans cold once.
    ///
    /// Still 2 with the optional `evicted` list (ids already counted and aged out, see
    /// `TranscriptScanner.tombstones`) and unsigned inodes: a version 2 file without the list
    /// decodes as "nothing evicted yet", and an older build skips the unknown key. A version bump
    /// would buy nothing here and cost a cold scan, which knows less history than the warm cache.
    static let version = 2

    // MARK: - JSON writing helpers

    @inline(__always) private static func put(_ buf: inout [UInt8], _ s: String) {
        buf.append(contentsOf: s.utf8)
    }

    @inline(__always) private static func putInt(_ buf: inout [UInt8], _ v: Int) {
        buf.append(contentsOf: String(v).utf8)
    }

    /// Sizes, offsets and inodes are written unsigned: `Int(UInt64)` traps from 2^63 up, which a
    /// hashed 64-bit inode (some FUSE and cloud file systems) reaches. Below 2^63 the text is the
    /// same as the signed writer produced, so older version 2 files read back unchanged.
    @inline(__always) private static func putUInt(_ buf: inout [UInt8], _ v: UInt64) {
        buf.append(contentsOf: String(v).utf8)
    }

    private static func putQuoted(_ buf: inout [UInt8], _ s: String) {
        buf.append(0x22)
        for b in s.utf8 {
            switch b {
            case 0x22, 0x5C: buf.append(0x5C); buf.append(b)
            case 0x08: put(&buf, "\\b")
            case 0x0C: put(&buf, "\\f")
            case 0x0A: put(&buf, "\\n")
            case 0x0D: put(&buf, "\\r")
            case 0x09: put(&buf, "\\t")
            case 0x00...0x1F: put(&buf, String(format: "\\u%04x", Int(b)))
            default: buf.append(b)
            }
        }
        buf.append(0x22)
    }

    // MARK: - Encode

    static func encode(files: [String: ScannedFile], evicted: [String: Double] = [:]) -> Data {
        var pool: [String: Int] = [:]
        var strings: [String] = []
        @inline(__always) func intern(_ s: String) -> Int {
            if let i = pool[s] { return i }
            let i = strings.count
            strings.append(s)
            pool[s] = i
            return i
        }

        // The string table is only complete once every event has been written, so the files array
        // is built first and the header is prepended afterwards.
        var body = [UInt8]()
        body.reserveCapacity(1 << 20)
        var firstFile = true
        for f in files.values.sorted(by: { $0.path < $1.path }) {
            if !firstFile { body.append(0x2C) }
            firstFile = false
            put(&body, "{\"p\":"); putQuoted(&body, f.path)
            put(&body, ",\"sz\":"); putUInt(&body, f.size)
            put(&body, ",\"mt\":"); put(&body, String(f.mtime.isFinite ? f.mtime : 0))
            put(&body, ",\"in\":"); putUInt(&body, f.inode)
            put(&body, ",\"of\":"); putUInt(&body, f.offset)
            put(&body, ",\"e\":[")
            var firstEvent = true
            for e in f.events {
                // Never write a row the reader rejects: that would discard the whole cache on every
                // launch. The parser already refuses such timestamps; this keeps the writer honest.
                guard isPlausibleEpoch(e.timestamp) else { continue }
                if !firstEvent { body.append(0x2C) }
                firstEvent = false
                body.append(0x5B)
                putInt(&body, Int((e.timestamp * 1000).rounded()))
                body.append(0x2C); putInt(&body, intern(e.sessionID))
                body.append(0x2C); putInt(&body, intern(e.model))
                body.append(0x2C); putInt(&body, intern(e.cwd))
                body.append(0x2C); putInt(&body, e.input)
                body.append(0x2C); putInt(&body, e.output)
                body.append(0x2C); putInt(&body, e.cacheWriteTotal)
                body.append(0x2C); putInt(&body, e.cacheWrite1h)
                body.append(0x2C); putInt(&body, e.cacheRead)
                body.append(0x2C); putInt(&body, e.fast ? 1 : 0)
                body.append(0x2C); putQuoted(&body, e.id)
                body.append(0x5D)
            }
            put(&body, "]}")
        }

        var out = [UInt8]()
        out.reserveCapacity(body.count + 4096 + strings.count * 40)
        put(&out, "{\"v\":"); putInt(&out, version)
        put(&out, ",\"savedAt\":"); putInt(&out, Int(Date().timeIntervalSince1970))
        put(&out, ",\"strings\":[")
        for (i, s) in strings.enumerated() {
            if i > 0 { out.append(0x2C) }
            putQuoted(&out, s)
        }
        put(&out, "],\"files\":[")
        out.append(contentsOf: body)
        put(&out, "],\"evicted\":[")
        // Grouped by UTC day, `[day, "id", "id", …]`: the time only decides when an id is
        // forgotten, so a day is precise enough, and a heavy user has ~100 000 of these ids, which
        // makes a timestamp per id a noticeable share of the file.
        var byDay: [Int: [String]] = [:]
        for (id, t) in evicted where isPlausibleEpoch(t) { byDay[Int(t / evictedDay), default: []].append(id) }
        var firstGroup = true
        for (day, ids) in byDay.sorted(by: { $0.key < $1.key }) {
            if !firstGroup { out.append(0x2C) }
            firstGroup = false
            out.append(0x5B); putInt(&out, day)
            for id in ids { out.append(0x2C); putQuoted(&out, id) }
            out.append(0x5D)
        }
        put(&out, "]}")
        return Data(out)
    }

    /// Granularity of the evicted-id times on disk.
    static let evictedDay: Double = 86_400

    // MARK: - Decode

    /// Read the cache straight into the scanner's structures.
    ///
    /// `JSONSerialization` would box every one of the ~300 000 numbers in this file as an
    /// `NSNumber`, which on a loaded machine costs well over a second — the whole point of the
    /// cache is that a relaunch is instant, so the file is parsed directly instead. Anything that
    /// does not match the expected shape makes the whole cache be discarded, and the scanner falls
    /// back to a cold scan.
    static func decode(_ data: Data) -> [String: ScannedFile]? { decodeState(data)?.files }

    /// Everything the file holds: per-file state plus the evicted-id memory (empty when the file
    /// predates it).
    static func decodeState(_ data: Data) -> ScanCacheState? {
        data.withUnsafeBytes { raw -> ScanCacheState? in
            var c = Reader(bytes: raw)
            return decodeRoot(&c)
        }
    }

    private static func decodeRoot(_ c: inout Reader) -> ScanCacheState? {
        guard c.openObject() else { return nil }
        var strings: [String] = []
        var out: [String: ScannedFile] = [:]
        var evicted: [String: Double] = [:]
        var sawVersion = false
        var sawFiles = false

        while let key = c.nextKey() {
            switch key {
            case "v":
                // Compared as a Double: `Int(v)` would trap on a `1e999` or NaN version.
                guard let v = c.number(), v == Double(version) else { return nil }
                sawVersion = true
            case "strings":
                guard c.openArray() else { return nil }
                while !c.closeArrayIfPresent() {
                    guard let s = c.string() else { return nil }
                    strings.append(s)
                    if !c.commaOrEnd() { return nil }
                }
            case "files":
                guard sawVersion else { return nil }   // version must come first; it does in our writer
                guard c.openArray() else { return nil }
                while !c.closeArrayIfPresent() {
                    guard let f = decodeFile(&c, strings: strings) else { return nil }
                    out[f.path] = f
                    if !c.commaOrEnd() { return nil }
                }
                sawFiles = true
            case "evicted":
                guard c.openArray() else { return nil }
                while !c.closeArrayIfPresent() {
                    guard c.openArray(), let day = c.number(), day == day.rounded(.down) else { return nil }
                    let t = day * evictedDay
                    guard isPlausibleEpoch(t) else { return nil }
                    while !c.closeArrayIfPresent() {
                        guard c.comma(), let id = c.string() else { return nil }
                        evicted[id] = t
                    }
                    if !c.commaOrEnd() { return nil }
                }
            default:
                guard c.skipValue() else { return nil }
            }
            if !c.commaOrEnd() { return nil }
        }
        // `nextKey` also ends the loop on a structural error; only a closing brace is success.
        guard !c.failed, sawVersion, sawFiles else { return nil }
        return ScanCacheState(files: out, evicted: evicted)
    }

    /// `UInt64(Double)` and `Int(Double)` **trap** on infinity, on NaN and on anything outside the
    /// integer's range, and a JSON number in a file we did not write can be any of those (a
    /// half-written cache, a disk error, a newer build). Every number that leaves the reader goes
    /// through one of these two, so a corrupt cache can only ever be *rejected*, never crash.
    @inline(__always) static func clampedUInt64(_ v: Double) -> UInt64 {
        guard v.isFinite, v > 0 else { return 0 }
        return v >= 9.2e18 ? 9_223_372_036_854_775_807 : UInt64(v)
    }

    @inline(__always) static func clampedInt(_ v: Double) -> Int {
        guard v.isFinite else { return 0 }
        if v >= 9.2e18 { return Int.max }
        if v <= -9.2e18 { return Int.min }
        return Int(v)
    }

    /// Epoch seconds a cached event is allowed to carry: 1970 … year 3000. Anything else means the
    /// file is not one of ours. The transcript parser applies the same range to every line, so a
    /// stray timestamp in a transcript is dropped there instead of poisoning the cache.
    static let maxEventEpoch: Double = 32_503_680_000

    @inline(__always) static func isPlausibleEpoch(_ t: Double) -> Bool {
        t.isFinite && t >= 0 && t <= maxEventEpoch
    }

    private static func decodeFile(_ c: inout Reader, strings: [String]) -> ScannedFile? {
        guard c.openObject() else { return nil }
        var f = ScannedFile(path: "")
        @inline(__always) func str(_ i: Int) -> String { (i >= 0 && i < strings.count) ? strings[i] : "" }

        while let key = c.nextKey() {
            switch key {
            case "p":
                guard let p = c.string() else { return nil }
                f.path = p
                f.sessionID = TranscriptScanner.sessionID(forPath: p)
            case "sz": guard let v = c.number() else { return nil }; f.size = clampedUInt64(v)
            case "mt": guard let v = c.number() else { return nil }; f.mtime = v.isFinite ? v : 0
            case "in":
                guard let v = c.numberToken() else { return nil }
                f.inode = v.exact ?? clampedUInt64(v.value)
            case "of": guard let v = c.number() else { return nil }; f.offset = clampedUInt64(v)
            case "e":
                guard c.openArray() else { return nil }
                while !c.closeArrayIfPresent() {
                    guard c.openArray() else { return nil }
                    guard let ms = c.number(), c.comma(),
                          let session = c.number(), c.comma(),
                          let model = c.number(), c.comma(),
                          let cwd = c.number(), c.comma(),
                          let input = c.number(), c.comma(),
                          let output = c.number(), c.comma(),
                          let writeTotal = c.number(), c.comma(),
                          let write1h = c.number(), c.comma(),
                          let read = c.number(), c.comma(),
                          let fast = c.number(), c.comma(),
                          let id = c.string(), c.closeArray() else { return nil }
                    guard fast == 0 || fast == 1 else { return nil }
                    let seconds = ms / 1000
                    // A timestamp outside the plausible epoch range means the row is not ours.
                    guard isPlausibleEpoch(seconds) else { return nil }
                    // Token counts are summed with trapping `+`, so a nonsense magnitude here would
                    // be an overflow crash later; reject the file instead.
                    for n in [input, output, writeTotal, write1h, read]
                    where !(n.isFinite && n >= 0 && n <= UsageEvent.maxTokenCount) { return nil }
                    f.events.append(UsageEvent(id: id,
                                               timestamp: seconds,
                                               sessionID: str(clampedInt(session)),
                                               cwd: str(clampedInt(cwd)),
                                               model: str(clampedInt(model)),
                                               input: max(0, clampedInt(input)),
                                               output: max(0, clampedInt(output)),
                                               cacheWriteTotal: max(0, clampedInt(writeTotal)),
                                               cacheWrite1h: max(0, clampedInt(write1h)),
                                               cacheRead: max(0, clampedInt(read)),
                                               fast: fast == 1))
                    if !c.commaOrEnd() { return nil }
                }
            default:
                guard c.skipValue() else { return nil }
            }
            if !c.commaOrEnd() { return nil }
        }
        guard !c.failed else { return nil }
        return f.path.isEmpty ? nil : f
    }

    // MARK: - Minimal JSON reader

    /// Just enough JSON for this one file format, without boxing anything.
    private struct Reader {
        let bytes: UnsafeRawBufferPointer
        var i = 0
        /// Set once a structural error is seen; every later call then fails too.
        var failed = false

        init(bytes: UnsafeRawBufferPointer) { self.bytes = bytes }

        @inline(__always) mutating func skipSpace() {
            while i < bytes.count {
                let b = bytes[i]
                if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1 } else { break }
            }
        }

        @inline(__always) mutating func peek() -> UInt8? {
            skipSpace()
            return i < bytes.count ? bytes[i] : nil
        }

        @inline(__always) mutating func take(_ c: UInt8) -> Bool {
            guard !failed, peek() == c else { return false }
            i += 1
            return true
        }

        mutating func openObject() -> Bool { take(0x7B) }
        mutating func openArray() -> Bool { take(0x5B) }
        mutating func closeArray() -> Bool { take(0x5D) }
        mutating func comma() -> Bool { take(0x2C) }

        /// True when the array ends here (consuming the bracket).
        mutating func closeArrayIfPresent() -> Bool { take(0x5D) }

        /// After a value: consume a comma, or stop at the closing bracket/brace.
        mutating func commaOrEnd() -> Bool {
            guard !failed else { return false }
            guard let c = peek() else { return false }
            if c == 0x2C { i += 1; return true }
            return c == 0x5D || c == 0x7D
        }

        /// Next `"key":` inside an object, or nil at its closing brace (which is consumed).
        mutating func nextKey() -> String? {
            guard !failed else { return nil }
            if take(0x7D) { return nil }
            guard let k = string(), take(0x3A) else { failed = true; return nil }
            return k
        }

        mutating func string() -> String? {
            guard !failed, take(0x22) else { failed = true; return nil }
            var scalars = [UInt8]()
            scalars.reserveCapacity(32)
            while i < bytes.count {
                let b = bytes[i]
                i += 1
                if b == 0x22 { return String(decoding: scalars, as: UTF8.self) }
                if b != 0x5C { scalars.append(b); continue }
                guard i < bytes.count else { break }
                let e = bytes[i]
                i += 1
                switch e {
                case 0x22, 0x5C, 0x2F: scalars.append(e)
                case 0x62: scalars.append(0x08)
                case 0x66: scalars.append(0x0C)
                case 0x6E: scalars.append(0x0A)
                case 0x72: scalars.append(0x0D)
                case 0x74: scalars.append(0x09)
                case 0x75:
                    guard i + 3 < bytes.count, let v = hex4(i) else { failed = true; return nil }
                    i += 4
                    if let scalar = Unicode.Scalar(v) {
                        scalars.append(contentsOf: Array(String(Character(scalar)).utf8))
                    }
                default: failed = true; return nil
                }
            }
            failed = true
            return nil
        }

        private func hex4(_ at: Int) -> UInt32? {
            var v: UInt32 = 0
            for k in 0..<4 {
                let b = bytes[at + k]
                let d: UInt32
                switch b {
                case 0x30...0x39: d = UInt32(b - 0x30)
                case 0x61...0x66: d = UInt32(b - 0x61) + 10
                case 0x41...0x46: d = UInt32(b - 0x41) + 10
                default: return nil
                }
                v = v << 4 | d
            }
            return v
        }

        mutating func number() -> Double? { numberToken()?.value }

        /// Exponent digits stop accumulating here. Anything past ±400 is already infinity or zero
        /// in a Double, so the cap changes no result; without it a 19-digit exponent is an `Int`
        /// overflow, which traps.
        static let exponentCap = 99_999

        /// One JSON number. `exact` is the value as an unsigned 64-bit integer when the text is a
        /// plain non-negative integer that fits (no sign, fraction or exponent) — the only way a
        /// hashed 64-bit inode survives the trip, since a Double keeps 53 bits. A value outside
        /// Double's range (a huge exponent, hundreds of digits, `0e999` = NaN) fails the whole
        /// read: our writer never produces one, so the file is not ours.
        mutating func numberToken() -> (value: Double, exact: UInt64?)? {
            guard !failed else { return nil }
            skipSpace()
            let start = i
            var negative = false
            if i < bytes.count, bytes[i] == 0x2D { negative = true; i += 1 }
            var value = 0.0
            var digits = 0
            var exact: UInt64? = 0
            while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 {
                let d = bytes[i] - 0x30
                value = value * 10 + Double(d)
                if let e = exact {
                    let (m, o1) = e.multipliedReportingOverflow(by: 10)
                    let (s, o2) = m.addingReportingOverflow(UInt64(d))
                    exact = (o1 || o2) ? nil : s
                }
                digits += 1
                i += 1
            }
            guard digits > 0 else { i = start; failed = true; return nil }
            var integral = !negative
            if i < bytes.count, bytes[i] == 0x2E {
                integral = false
                i += 1
                var scale = 0.1
                while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 {
                    value += Double(bytes[i] - 0x30) * scale
                    scale /= 10
                    i += 1
                }
            }
            if i < bytes.count, bytes[i] == 0x65 || bytes[i] == 0x45 {
                integral = false
                i += 1
                var expNegative = false
                if i < bytes.count, bytes[i] == 0x2B || bytes[i] == 0x2D {
                    expNegative = bytes[i] == 0x2D
                    i += 1
                }
                var exp = 0
                while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 {
                    if exp <= Reader.exponentCap { exp = exp * 10 + Int(bytes[i] - 0x30) }
                    i += 1
                }
                value *= pow(10, Double(expNegative ? -exp : exp))
            }
            let signed = negative ? -value : value
            guard signed.isFinite else { failed = true; return nil }
            return (signed, integral ? exact : nil)
        }

        /// Skip any value, so a cache written by a newer build with extra keys still loads.
        mutating func skipValue() -> Bool {
            guard !failed, let c = peek() else { return false }
            switch c {
            case 0x22: return string() != nil
            case 0x7B, 0x5B:
                var depth = 0
                repeat {
                    guard let ch = peek() else { return false }
                    if ch == 0x22 {
                        guard string() != nil else { return false }
                        continue
                    }
                    i += 1
                    if ch == 0x7B || ch == 0x5B { depth += 1 }
                    if ch == 0x7D || ch == 0x5D { depth -= 1 }
                } while depth > 0
                return true
            case 0x74: i += 4; return i <= bytes.count          // true
            case 0x66: i += 5; return i <= bytes.count          // false
            case 0x6E: i += 4; return i <= bytes.count          // null
            default: return number() != nil
            }
        }
    }
}

/// What the scan cache file holds.
struct ScanCacheState {
    var files: [String: ScannedFile]
    /// `message.id` -> timestamp (epoch seconds) of responses already counted and evicted.
    var evicted: [String: Double]
}
