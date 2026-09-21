import Foundation
import UsageCore
import UsageModel

// usage-dump — a CLI over UsageCore, so the data layer can be exercised and verified without any UI.
//
//   usage-dump [--once] [--no-live] [--json] [--selftest] [--watch N] [--fsprobe] [--timeout S]
//
// Nothing here ever prints transcript content: only counts, ids, model names, timestamps, token
// numbers, byte offsets and paths.

// MARK: - Options

struct Options {
    var once = true
    var live = true
    var json = false
    var selftest = false
    var watchSeconds: Double?
    var fsprobe = false
    var timeout: Double = 120
    var sessionLimit = 14

    static func parse(_ argv: [String]) -> Options {
        var o = Options()
        var i = 0
        while i < argv.count {
            switch argv[i] {
            case "--once": o.once = true
            case "--no-live": o.live = false
            case "--json": o.json = true
            case "--selftest": o.selftest = true
            case "--fsprobe": o.fsprobe = true
            case "--watch":
                i += 1
                o.watchSeconds = i < argv.count ? (Double(argv[i]) ?? 20) : 20
                o.once = false
            case "--timeout":
                i += 1
                if i < argv.count, let v = Double(argv[i]) { o.timeout = v }
            case "--sessions":
                i += 1
                if i < argv.count, let v = Int(argv[i]) { o.sessionLimit = v }
            case "-h", "--help":
                print("""
                usage-dump [--once] [--no-live] [--json] [--selftest] [--watch SECONDS] [--fsprobe]
                           [--timeout SECONDS] [--sessions N]

                  --once      wait for the first complete scan, print one snapshot, exit (default)
                  --no-live   do not touch the account API or the credential at all
                  --json      print the snapshot as JSON instead of a table
                  --selftest  run the pure-logic assertions and exit non-zero on failure
                  --watch N   print one compact line per published snapshot for N seconds
                  --fsprobe   measure file-change -> published-snapshot latency on a scratch tree
                """)
                exit(0)
            default:
                if argv[i].hasPrefix("--") {
                    FileHandle.standardError.write(Data("usage-dump: unknown option \(argv[i])\n".utf8))
                    exit(2)
                }
            }
            i += 1
        }
        return o
    }
}

// MARK: - Formatting

func fmtTokens(_ n: Int) -> String {
    let d = Double(n)
    switch abs(d) {
    case 0..<1_000: return "\(n)"
    case 1_000..<1_000_000: return String(format: "%.1fK", d / 1_000)
    case 1_000_000..<1_000_000_000: return String(format: "%.2fM", d / 1_000_000)
    default: return String(format: "%.2fG", d / 1_000_000_000)
    }
}

func fmtUSD(_ v: Double) -> String {
    if abs(v) >= 1000 { return String(format: "$%.0f", v) }
    if abs(v) >= 10 { return String(format: "$%.2f", v) }
    return String(format: "$%.3f", v)
}

func fmtDuration(_ seconds: TimeInterval) -> String {
    let s = Int(max(0, seconds.rounded()))
    if s >= 86_400 { return "\(s / 86_400)d\((s % 86_400) / 3_600)h" }
    if s >= 3_600 { return "\(s / 3_600)h\((s % 3_600) / 60)m" }
    if s >= 60 { return "\(s / 60)m\(s % 60)s" }
    return "\(s)s"
}

let clockFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

let resetFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE HH:mm"
    return f
}()

let stampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZ"
    return f
}()

func bar(_ percent: Double, width: Int = 20) -> String {
    let filled = Int((percent / 100 * Double(width)).rounded())
    return "[" + String(repeating: "#", count: min(width, max(0, filled)))
        + String(repeating: ".", count: max(0, width - max(0, filled))) + "]"
}

func pad(_ s: String, _ n: Int) -> String {
    if s.count >= n { return String(s.prefix(n)) }
    return s + String(repeating: " ", count: n - s.count)
}

func padLeft(_ s: String, _ n: Int) -> String {
    if s.count >= n { return String(s.prefix(n)) }
    return String(repeating: " ", count: n - s.count) + s
}

func describe(_ status: LiveStatus) -> String {
    switch status {
    case .disabled: return "disabled"
    case .neverFetched: return "never fetched"
    case .ok(let at): return "ok (\(fmtDuration(Date().timeIntervalSince(at))) ago)"
    case .authExpired: return "AUTH EXPIRED - open Claude Code to refresh"
    case .rateLimited(let retryAt): return "rate limited (retry in \(fmtDuration(retryAt.timeIntervalSinceNow)))"
    case .error(let message): return "error: \(message)"
    }
}

// MARK: - Human table

func printTable(_ s: UsageSnapshot, _ d: ScanDiagnostics, coldSeconds: Double, firstDataSeconds: Double?,
                sessionLimit: Int = 14) {
    let line = String(repeating: "-", count: 78)
    print("TOKENAMP usage-dump" + padLeft(stampFormatter.string(from: s.generatedAt), 78 - 19))
    print("plan " + (s.planName.isEmpty ? "(unknown)" : s.planName)
        + "   live: " + describe(s.liveStatus)
        + "   local: \(s.localStatus.filesDone)/\(s.localStatus.filesTotal) files"
        + (s.localStatus.isScanning ? " (scanning)" : ""))
    print(line)
    if s.limits.isEmpty {
        print(" (no plan limits available)")
    } else {
        for g in s.limits {
            var reset = "reset unknown"
            if let r = g.resetsAt {
                let soon = r.timeIntervalSinceNow
                reset = (soon < 12 * 3600 ? clockFormatter.string(from: r) : resetFormatter.string(from: r))
                    + "  (in " + fmtDuration(soon) + ")"
            }
            print(" " + pad(g.title, 20) + " " + bar(g.percent)
                + padLeft(String(format: "%.1f%%", g.percent), 8) + "  " + reset
                + (g.isActive ? "  *" : "")
                + (g.severity != "normal" ? "  [\(g.severity)]" : ""))
        }
    }
    print(line)
    let t = s.today.tokens
    print("today   " + pad(fmtTokens(t.total) + " tok", 14)
        + "in " + fmtTokens(t.input) + " / out " + fmtTokens(t.output)
        + " / cache-w " + fmtTokens(t.cacheWrite) + " / cache-r " + fmtTokens(t.cacheRead))
    print("        " + pad(fmtUSD(s.today.costUSD), 14) + "\(s.today.messages) messages"
        + "   fresh " + fmtTokens(t.fresh))
    print("burn    " + pad(fmtTokens(Int(s.burnTokensPerMin)) + "/min", 14)
        + String(format: "%.2f $/hr", s.burnUSDPerHour)
        + "   active sessions: \(s.activeSessionCount)"
        + (s.lastEventAt.map { "   last event \(fmtDuration(Date().timeIntervalSince($0))) ago" } ?? ""))
    print(line)
    print("sessions today: \(s.sessionsToday.count)")
    let shown = max(0, sessionLimit)
    for (i, row) in s.sessionsToday.prefix(shown).enumerated() {
        print(String(format: "%3d. ", i + 1) + pad(row.project, 34) + pad(row.model, 12)
            + padLeft(fmtTokens(row.tokens.total), 9) + padLeft(fmtUSD(row.costUSD), 11)
            + padLeft("\(row.messages) msg", 9)
            + "  " + clockFormatter.string(from: row.lastActivity)
            + (row.isActive ? "  ACTIVE" : ""))
    }
    if s.sessionsToday.count > shown { print("     ... and \(s.sessionsToday.count - shown) more") }
    print(line)

    let fineNonZero = s.fine.filter { $0.messages > 0 }.count
    let minutesNonZero = s.minutes.filter { $0.messages > 0 }.count
    print("buckets  fine \(s.fine.count)x5s (\(fineNonZero) active)"
        + "  minutes \(s.minutes.count) (\(minutesNonZero) active)"
        + "  hours \(s.hours.count)  days \(s.days.count)")
    print("days     " + s.days.map { fmtTokens($0.tokens.total) }.joined(separator: " "))
    print("day $    " + s.days.map { String(format: "%.0f", $0.costUSD) }.joined(separator: " "))
    print(line)
    print("scan     \(d.filesConsidered) files in window, \(d.filesParsed) read, "
        + String(format: "%.2f GB read this run (%.2f GB in the last pass)", Double(d.bytesRead) / 1_073_741_824, Double(d.lastScanBytes) / 1_073_741_824)
        + String(format: ", last pass %.2fs = %.0f MB/s", d.lastFullScanSeconds, d.throughputMBPerSecond))
    print("events   \(d.rawEvents) raw / \(d.uniqueEvents) unique, "
        + "\(d.linesPrefiltered) lines passed the byte prefilter, \(d.linesParsed) JSON-parsed")
    print("         \(d.fastEvents) fast-mode, \(d.sharedEvents) carried by more than one transcript")
    print("timing   " + String(format: "complete in %.2fs", coldSeconds)
        + (firstDataSeconds.map { String(format: ", today's data first shown at %.2fs", $0) } ?? "")
        + (d.loadedFromCache ? String(format: ", warm cache load %.3fs", d.cacheLoadSeconds) : ", cold (no cache)")
        + String(format: ", worst snapshot rebuild %.1f ms", d.maxSnapshotBuildSeconds * 1000))
    print("root     " + d.transcriptRoot)
}

// MARK: - JSON

func printJSON(_ s: UsageSnapshot) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(s), let text = String(data: data, encoding: .utf8) {
        print(text)
    } else {
        FileHandle.standardError.write(Data("usage-dump: could not encode snapshot\n".utf8))
        exit(1)
    }
}

// MARK: - Watch

func compactLine(_ s: UsageSnapshot) -> String {
    let fineTail = s.fine.suffix(12).map { $0.messages > 0 ? "\($0.messages)" : "." }.joined()
    let session = s.limits.first { $0.kind == .session }.map { String(format: "%.1f%%", $0.percent) } ?? "--"
    return clockFormatter.string(from: s.generatedAt)
        + "  today " + padLeft(fmtTokens(s.today.tokens.total), 8)
        + " " + padLeft(fmtUSD(s.today.costUSD), 9)
        + " msgs " + padLeft("\(s.today.messages)", 6)
        + "  fine[" + fineTail + "]"
        + "  burn " + padLeft(fmtTokens(Int(s.burnTokensPerMin)), 7) + "/min"
        + "  act " + "\(s.activeSessionCount)"
        + "  sess " + session
        + "  last " + padLeft(s.lastEventAt.map { fmtDuration(Date().timeIntervalSince($0)) } ?? "-", 5)
        + "  live " + describe(s.liveStatus)
}

// MARK: - FS probe

/// Measures file-change -> published-snapshot latency on a scratch tree, so no real transcript is
/// touched or read.
func runFSProbe() -> Never {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("tokenamp-fsprobe-\(UInt32.random(in: 0...UInt32.max))", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("99999999-9999-9999-9999-999999999999.jsonl")
    FileManager.default.createFile(atPath: file.path, contents: Data())

    let provider = LiveUsageProvider(root: dir,
                                     cacheURL: dir.appendingPathComponent("scan-cache.json"),
                                     pricingURL: dir.appendingPathComponent("pricing.json"))
    provider.isLiveEnabled = false

    var sent = Date()
    var pending: String?
    var samples: [Double] = []
    let rounds = 6

    func fire() {
        let id = "probe_\(samples.count)_\(UInt32.random(in: 0...UInt32.max))"
        pending = id
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: Date())
        let line = "{\"type\":\"assistant\",\"timestamp\":\"\(ts)\",\"sessionId\":\"probe\",\"cwd\":\"/tmp/probe\",\"message\":{\"id\":\"\(id)\",\"model\":\"claude-opus-5\",\"role\":\"assistant\",\"content\":[],\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"cache_creation_input_tokens\":3,\"cache_read_input_tokens\":4}}}\n"
        sent = Date()
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        }
    }

    provider.onChange = { snap in
        guard pending != nil else { return }
        guard snap.today.messages >= samples.count + 1 else { return }
        let latency = Date().timeIntervalSince(sent)
        samples.append(latency)
        pending = nil
        print(String(format: "  probe %d: %.0f ms", samples.count, latency * 1000))
        if samples.count >= rounds {
            provider.stop()
            let mean = samples.reduce(0, +) / Double(samples.count)
            print(String(format: "fsprobe: %d samples, min %.0f ms, mean %.0f ms, max %.0f ms",
                         samples.count, (samples.min() ?? 0) * 1000, mean * 1000, (samples.max() ?? 0) * 1000))
            try? FileManager.default.removeItem(at: dir)
            exit(0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { fire() }
    }
    provider.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { fire() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 40) {
        print("fsprobe: timed out after \(samples.count) samples")
        try? FileManager.default.removeItem(at: dir)
        exit(samples.isEmpty ? 1 : 0)
    }
    RunLoop.main.run()
    exit(0)
}

// MARK: - Main

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))

if options.selftest {
    exit(SelfTest.run() ? 0 : 1)
}

if options.fsprobe {
    runFSProbe()
}

let started = Date()
let provider = LiveUsageProvider()
provider.isLiveEnabled = options.live
provider.start()

if let seconds = options.watchSeconds {
    var lines = 0
    provider.onChange = { snap in
        lines += 1
        print(compactLine(snap))
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        provider.stop()
        print("watch: \(lines) snapshots in \(Int(seconds))s")
        exit(0)
    }
    RunLoop.main.run()
} else {
    // When did the user first see today's numbers? That is the "cold start" that matters.
    var firstDataSeconds: Double?
    provider.onChange = { snap in
        if firstDataSeconds == nil, snap.today.tokens.total > 0 {
            firstDataSeconds = Date().timeIntervalSince(started)
        }
    }
    let poll = Timer(timeInterval: 0.05, repeats: true) { timer in
        let snap = provider.snapshot
        let diag = provider.diagnostics
        let elapsed = Date().timeIntervalSince(started)
        let scanDone = diag.firstScanComplete
        let liveDone = !options.live || snap.liveStatus != .neverFetched
        guard (scanDone && liveDone) || elapsed > options.timeout else { return }
        timer.invalidate()
        provider.stop()
        if !scanDone || !liveDone {
            FileHandle.standardError.write(Data("usage-dump: timed out after \(Int(elapsed))s; printing what is known\n".utf8))
        }
        if options.json {
            printJSON(snap)
        } else {
            printTable(snap, diag, coldSeconds: elapsed, firstDataSeconds: firstDataSeconds,
                       sessionLimit: options.sessionLimit)
        }
        exit(0)
    }
    RunLoop.main.add(poll, forMode: .common)
    RunLoop.main.run()
}
