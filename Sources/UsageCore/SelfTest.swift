import Foundation
import UsageModel

/// Assertion-style checks over the pure logic of the data layer. This is what stands in for XCTest
/// (there is no Xcode on this machine), and it is what `usage-dump --selftest` runs.
///
/// Everything here works on synthetic data written into a temporary directory. No real transcript
/// is ever read, printed or parsed by the self-test.
public enum SelfTest {

    public static func run(verbose: Bool = true) -> Bool {
        var runner = Runner(verbose: verbose)

        pricing(&runner)
        displayNames(&runner)
        timestamps(&runner)
        dedup(&runner)
        buckets(&runner)
        tailing(&runner)
        windowAndEviction(&runner)
        limitsParsing(&runner)
        cacheRoundTrip(&runner)
        planNames(&runner)
        hostileCache(&runner)
        localTimeAndDST(&runner)
        clockSkew(&runner)
        activityWindows(&runner)
        rescanAfterPartialLine(&runner)
        attributionDeterminism(&runner)
        parallelScan(&runner)
        providerLifecycle(&runner)

        runner.summary()
        return runner.failures == 0
    }

    // MARK: - Runner

    struct Runner {
        let verbose: Bool
        var checks = 0
        var failures = 0
        var group = ""

        mutating func section(_ name: String) {
            group = name
            if verbose { print("• \(name)") }
        }

        mutating func expect(_ condition: Bool, _ what: @autoclosure () -> String) {
            checks += 1
            if !condition {
                failures += 1
                print("  FAIL [\(group)] \(what())")
            }
        }

        mutating func equal<T: Equatable>(_ a: T, _ b: T, _ what: String) {
            checks += 1
            if a != b {
                failures += 1
                print("  FAIL [\(group)] \(what): got \(a), expected \(b)")
            }
        }

        mutating func close(_ a: Double, _ b: Double, _ tolerance: Double, _ what: String) {
            checks += 1
            if !(abs(a - b) <= tolerance) {
                failures += 1
                print("  FAIL [\(group)] \(what): got \(a), expected \(b) ± \(tolerance)")
            }
        }

        func summary() {
            if failures == 0 {
                print("selftest: \(checks) checks passed")
            } else {
                print("selftest: \(failures) of \(checks) checks FAILED")
            }
        }
    }

    // MARK: - Pricing

    static func pricing(_ r: inout Runner) {
        r.section("pricing")
        let table = PricingTable.builtIn
        r.equal(table.price(for: "claude-fable-5-1").input, 10, "fable input")
        r.equal(table.price(for: "claude-fable-5-1").output, 50, "fable output")
        r.equal(table.price(for: "claude-mythos-1").input, 10, "mythos input")
        r.equal(table.price(for: "claude-opus-5").input, 5, "opus-5 input")
        r.equal(table.price(for: "claude-opus-5").output, 25, "opus-5 output")
        r.equal(table.price(for: "claude-opus-4-5-20250929").input, 5, "opus-4-5 input")
        r.equal(table.price(for: "claude-opus-4-1-20250805").input, 15, "older opus input")
        r.equal(table.price(for: "claude-sonnet-5").input, 2, "sonnet-5 input")
        r.equal(table.price(for: "claude-sonnet-4-5-20250929").input, 3, "sonnet-4-5 input")
        r.equal(table.price(for: "claude-haiku-4-5-20251001").input, 1, "haiku-4-5 input")
        r.equal(table.price(for: "claude-3-haiku-20240307").input, 0.25, "old haiku input")
        r.equal(table.price(for: "some-unknown-model").input, 3, "fallback input")
        r.equal(table.price(for: "some-unknown-model").output, 15, "fallback output")

        let resolver = PricingResolver(table: table)
        // 1M input, 1M output, 1M 5m-write, 1M 1h-write, 1M cache read on opus-5 (5 / 25):
        //   5 + 25 + 6.25 + 10 + 0.5 = 46.75
        let full = resolver.cost(model: "claude-opus-5", input: 1_000_000, output: 1_000_000,
                                 cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000, cacheRead: 1_000_000)
        r.close(full, 46.75, 1e-9, "opus-5 blended cost")

        // Cache split matters: 1M of 1h writes costs 2x input, 1M of 5m writes costs 1.25x input.
        let write5 = resolver.cost(model: "claude-opus-5", input: 0, output: 0, cacheWrite5m: 1_000_000, cacheWrite1h: 0, cacheRead: 0)
        let write1h = resolver.cost(model: "claude-opus-5", input: 0, output: 0, cacheWrite5m: 0, cacheWrite1h: 1_000_000, cacheRead: 0)
        r.close(write5, 6.25, 1e-9, "5m cache write")
        r.close(write1h, 10.0, 1e-9, "1h cache write")
        r.expect(write1h > write5, "1h writes must cost more than 5m writes")

        // Missing split -> everything at the 5 m rate.
        let noSplit = makeEvent(id: "a", ts: 0, model: "claude-opus-5", input: 0, output: 0, writeTotal: 1_000_000, write1h: 0, read: 0)
        r.close(resolver.cost(model: noSplit.model, input: noSplit.input, output: noSplit.output,
                              cacheWrite5m: noSplit.cacheWrite5m, cacheWrite1h: noSplit.cacheWrite1h,
                              cacheRead: noSplit.cacheRead), 6.25, 1e-9, "absent split priced at 5m")

        // User override file.
        let override = Data("""
        {"models":[{"match":"fable","input":1,"output":2},{"match":"*","input":9,"output":9}]}
        """.utf8)
        guard let parsed = PricingTable.parse(override) else {
            r.expect(false, "pricing.json override failed to parse")
            return
        }
        r.equal(parsed.price(for: "claude-fable-5-1").input, 1, "override fable input")
        r.equal(parsed.price(for: "claude-opus-5").input, 9, "override fallback input")
        // Round trip through the generated default file.
        guard let reparsed = PricingTable.parse(PricingTable.builtIn.jsonData()) else {
            r.expect(false, "generated pricing.json failed to re-parse")
            return
        }
        r.equal(reparsed, PricingTable.builtIn, "pricing.json round trip")
    }

    // MARK: - Display names

    static func displayNames(_ r: inout Runner) {
        r.section("model display names")
        r.equal(ModelDisplayName.of("claude-fable-5-1"), "FABLE 5.1", "fable")
        r.equal(ModelDisplayName.of("claude-opus-5"), "OPUS 5", "opus 5")
        r.equal(ModelDisplayName.of("claude-haiku-4-5-20251001"), "HAIKU 4.5", "haiku dated")
        r.equal(ModelDisplayName.of("claude-sonnet-5"), "SONNET 5", "sonnet 5")
        r.equal(ModelDisplayName.of("claude-3-5-sonnet-20241022"), "SONNET 3.5", "legacy ordering")
        r.equal(ModelDisplayName.of("us.anthropic.claude-opus-5-v1:0"), "OPUS 5", "vendor prefixed")
        r.equal(ModelDisplayName.of("claude-opus-5[1m]"), "OPUS 5 [1M]", "context suffix survives")
    }

    // MARK: - Timestamps

    static func timestamps(_ r: inout Runner) {
        r.section("ISO-8601")
        // 2026-09-20T20:57:11.277Z
        let a = ISO8601.epochSeconds("2026-09-20T20:57:11.277Z")
        r.expect(a != nil, "3-digit fraction parsed")
        r.close(a ?? 0, 1_789_937_831.277, 1e-3, "3-digit fraction value")

        let b = ISO8601.epochSeconds("2026-09-21T01:50:00.324734+00:00")
        r.expect(b != nil, "6-digit fraction with +00:00 parsed")
        r.close(b ?? 0, 1_789_955_400.324734, 1e-5, "6-digit fraction value")

        let c = ISO8601.epochSeconds("2026-09-20T20:57:11Z")
        r.close(c ?? 0, 1_789_937_831, 1e-6, "no fraction")

        let d = ISO8601.epochSeconds("2026-09-20T22:57:11.000+02:00")
        r.close(d ?? 0, 1_789_937_831, 1e-6, "positive offset")

        let e = ISO8601.epochSeconds("2026-09-20T18:57:11.000-02:00")
        r.close(e ?? 0, 1_789_937_831, 1e-6, "negative offset")

        let f = ISO8601.epochSeconds("2026-09-20T18:57:11.000-0200")
        r.close(f ?? 0, 1_789_937_831, 1e-6, "offset without colon")

        r.expect(ISO8601.epochSeconds("not a timestamp") == nil, "garbage rejected")
        r.expect(ISO8601.epochSeconds("") == nil, "empty rejected")

        // Cross-check a handful of instants against Foundation.
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        for s in ["2024-02-29T12:00:00Z", "2000-01-01T00:00:00Z", "2026-12-31T23:59:59Z", "1999-03-01T05:06:07Z"] {
            let mine = ISO8601.epochSeconds(s) ?? -1
            let theirs = fmt.date(from: s)?.timeIntervalSince1970 ?? -2
            r.close(mine, theirs, 1e-6, "cross-check \(s)")
        }
    }

    // MARK: - Dedup

    static func dedup(_ r: inout Runner) {
        r.section("global dedup")
        // One API response written as four content-block lines with growing output_tokens.
        var merged = makeEvent(id: "msg_1", ts: 1000, model: "claude-opus-5", input: 12, output: 40, writeTotal: 900, write1h: 100, read: 5000)
        for out in [128, 512, 1337] {
            var next = makeEvent(id: "msg_1", ts: 1002, model: "claude-opus-5", input: 12, output: out, writeTotal: 900, write1h: 100, read: 5000)
            next.sessionID = "other-session"
            merged.merge(next)
        }
        r.equal(merged.output, 1337, "last/max output_tokens wins")
        r.equal(merged.input, 12, "input unchanged")
        r.equal(merged.cacheRead, 5000, "cache read unchanged")
        r.equal(merged.sessionID, "session-a", "first session keeps the event")
        r.close(merged.timestamp, 1002, 1e-9, "timestamp advances to the last line")

        // End to end through the scanner: the same id in two files counts once.
        guard let dir = makeTempDir() else { r.expect(false, "temp dir"); return }
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = Date().timeIntervalSince1970 - 60
        let s1 = dir.appendingPathComponent("11111111-1111-1111-1111-111111111111.jsonl")
        let s2 = dir.appendingPathComponent("22222222-2222-2222-2222-222222222222.jsonl")
        writeLines(to: s1, [
            assistantLine(id: "dup_1", ts: base, model: "claude-opus-5", output: 10),
            assistantLine(id: "dup_1", ts: base + 1, model: "claude-opus-5", output: 250),
            assistantLine(id: "uniq_1", ts: base + 2, model: "claude-opus-5", output: 7),
        ])
        writeLines(to: s2, [
            assistantLine(id: "dup_1", ts: base, model: "claude-opus-5", output: 250),
            assistantLine(id: "uniq_2", ts: base + 3, model: "claude-sonnet-5", output: 9),
        ])
        let scanner = TranscriptScanner(root: dir)
        scanner.fullScan(now: Date())
        r.equal(scanner.uniqueEventCount, 3, "three unique ids across two files")
        let byID = Dictionary(uniqueKeysWithValues: scanner.sortedEvents().map { ($0.id, $0) })
        r.equal(byID["dup_1"]?.output ?? -1, 250, "growing output_tokens folded")
        r.equal(scanner.sortedEvents().count, 3, "sorted events deduped")
        r.expect(scanner.sortedEvents().map { $0.timestamp } == scanner.sortedEvents().map { $0.timestamp }.sorted(), "sorted ascending")

        // Subagent transcripts are attributed to the parent session directory.
        let parent = "33333333-3333-3333-3333-333333333333"
        let subDir = dir.appendingPathComponent("\(parent)/subagents/workflows/wf_x", isDirectory: true)
        try? FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let subFile = subDir.appendingPathComponent("agent-abc.jsonl")
        writeLines(to: subFile, [assistantLine(id: "sub_1", ts: base + 4, model: "claude-haiku-4-5", output: 3, sessionID: "some-other-id")])
        r.equal(TranscriptScanner.sessionID(forPath: subFile.path), parent, "subagent attributed to parent dir")
        let scanner2 = TranscriptScanner(root: dir)
        scanner2.fullScan(now: Date())
        let sub = scanner2.sortedEvents().first { $0.id == "sub_1" }
        r.equal(sub?.sessionID ?? "", parent, "subagent event carries the parent session id")

        // Synthetic models are skipped entirely.
        let s3 = dir.appendingPathComponent("44444444-4444-4444-4444-444444444444.jsonl")
        writeLines(to: s3, [assistantLine(id: "syn_1", ts: base + 5, model: "<synthetic>", output: 5)])
        let scanner3 = TranscriptScanner(root: dir)
        scanner3.fullScan(now: Date())
        r.expect(!scanner3.sortedEvents().contains { $0.id == "syn_1" }, "<synthetic> skipped")
    }

    // MARK: - Buckets

    static func buckets(_ r: inout Runner) {
        r.section("bucket alignment")
        let pricingResolver = PricingResolver()
        let agg = Aggregator(pricing: pricingResolver)
        let now = Date(timeIntervalSince1970: 1_789_940_232.7)   // deliberately mid-bucket
        var events: [UsageEvent] = []
        // one event 7 s ago, one 90 s ago, one 5 h ago, one 3 days ago
        for (i, back) in [7.0, 90.0, 5 * 3600.0, 3 * 86400.0].enumerated() {
            events.append(makeEvent(id: "e\(i)", ts: now.timeIntervalSince1970 - back, model: "claude-opus-5",
                                    input: 100, output: 200, writeTotal: 1000, write1h: 0, read: 10_000))
        }
        events.sort { $0.timestamp < $1.timestamp }
        let snap = agg.snapshot(events: events, now: now, planName: "MAX 20X", limits: [],
                                liveStatus: .neverFetched, localStatus: LocalStatus())

        r.equal(snap.fine.count, UsageSnapshot.fineBucketCount, "fine count")
        r.equal(snap.minutes.count, UsageSnapshot.minuteBucketCount, "minute count")
        r.equal(snap.hours.count, UsageSnapshot.hourBucketCount, "hour count")
        r.equal(snap.days.count, UsageSnapshot.dayBucketCount, "day count")

        // Alignment: each grid is a multiple of its own duration since the epoch, ascending, and the
        // last bucket contains `now`.
        for (name, array, step) in [("fine", snap.fine, 5.0), ("minutes", snap.minutes, 60.0), ("hours", snap.hours, 3600.0)] {
            for b in array {
                r.close(b.start.timeIntervalSince1970.truncatingRemainder(dividingBy: step), 0, 1e-6, "\(name) aligned to \(Int(step))s")
                r.close(b.duration, step, 1e-9, "\(name) duration")
            }
            for k in 1..<array.count {
                r.close(array[k].start.timeIntervalSince1970 - array[k - 1].start.timeIntervalSince1970, step, 1e-6, "\(name) contiguous")
            }
            let last = array[array.count - 1]
            r.expect(last.start <= now && now < last.start.addingTimeInterval(step), "\(name) last bucket is the partial one covering now")
        }

        let cal = Calendar.current
        r.equal(snap.days[snap.days.count - 1].start, cal.startOfDay(for: now), "last day bucket starts today")
        r.equal(snap.today, snap.days[snap.days.count - 1], "today == last day bucket")

        // Placement.
        r.equal(snap.fine[UsageSnapshot.fineBucketCount - 2].messages, 1, "event 7 s ago lands one bucket back")
        r.equal(snap.fine[57].messages, 1, "event 90 s ago lands 18 buckets back")
        r.equal(snap.fine.reduce(0) { $0 + $1.messages }, 2, "the 7 s and 90 s events are inside the 6 min 20 s window")
        r.equal(snap.minutes.reduce(0) { $0 + $1.messages }, 2, "two events inside the last hour")
        r.equal(snap.hours.reduce(0) { $0 + $1.messages }, 3, "three events inside the last 24 h")
        r.equal(snap.days.reduce(0) { $0 + $1.messages }, 4, "all four inside the last 10 days")

        // Burn: the events 7 s and 90 s ago are inside the 5 minute window; cache reads are excluded.
        let freshIn5min = 2 * (100 + 200 + 1000)
        r.close(snap.burnTokensPerMin, Double(freshIn5min) / 5, 1e-6, "burn tokens/min")
        r.expect(snap.burnUSDPerHour > 0, "burn cost positive")
        r.equal(snap.lastEventAt.map { Int($0.timeIntervalSince1970) } ?? 0, Int(now.timeIntervalSince1970 - 7), "last event")

        // An empty history still produces correctly shaped arrays.
        let empty = agg.snapshot(events: [], now: now, planName: "", limits: [], liveStatus: .disabled, localStatus: LocalStatus())
        r.equal(empty.fine.count, UsageSnapshot.fineBucketCount, "empty fine count")
        r.equal(empty.days.count, UsageSnapshot.dayBucketCount, "empty day count")
        r.equal(empty.today.tokens.total, 0, "empty today")
        r.expect(empty.lastEventAt == nil, "no last event")

        r.section("project labels")
        let home = NSHomeDirectory()
        r.equal(agg.projectName(for: home + "/Documents/tests/fable5dot1/claude-usage-amp", sessionID: "x"),
                "fable5dot1/claude-usage-amp", "two trailing components")
        r.equal(agg.projectName(for: home, sessionID: "x"), "~", "home itself")
        r.equal(agg.projectName(for: "/tmp", sessionID: "x"), "tmp", "single component")
        r.equal(agg.projectName(for: home + "/Library/Application Support/Claude/scratch-workspaces/28e9f5fc-6789-4058-942b-d18a6b3eae0b/48793b39-359c-4729-a407-fd3afa6321f3/scratch-2026-09-20", sessionID: "x"),
                "scratch-workspaces/scratch-2026-09-20", "uuid directories dropped")
        r.expect(Aggregator.looksLikeUUID("48793b39-359c-4729-a407-fd3afa6321f3"), "uuid recognised")
        r.expect(!Aggregator.looksLikeUUID("claude-usage-amp"), "project name is not a uuid")
        r.equal(agg.projectName(for: "", sessionID: "abcdefgh-1234"), "abcdefgh", "no cwd falls back to the session id")
    }

    // MARK: - Incremental tailing

    static func tailing(_ r: inout Runner) {
        r.section("incremental tailing")
        guard let dir = makeTempDir() else { r.expect(false, "temp dir"); return }
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("55555555-5555-5555-5555-555555555555.jsonl")
        let base = Date().timeIntervalSince1970 - 300

        writeLines(to: file, [
            assistantLine(id: "t1", ts: base, model: "claude-opus-5", output: 11),
            assistantLine(id: "t2", ts: base + 1, model: "claude-opus-5", output: 12),
        ])
        let scanner = TranscriptScanner(root: dir)
        scanner.fullScan(now: Date())
        r.equal(scanner.uniqueEventCount, 2, "initial pass")
        let offsetAfterFirst = scanner.files[file.path]?.offset ?? 0
        r.equal(Int(offsetAfterFirst), fileSize(file), "offset consumed the whole file")

        // Append a complete line plus a partial one with no newline yet.
        let partial = assistantLine(id: "t4", ts: base + 3, model: "claude-opus-5", output: 14)
        append(to: file, assistantLine(id: "t3", ts: base + 2, model: "claude-opus-5", output: 13) + "\n" + partial)
        r.expect(scanner.tail(paths: [file.path], now: Date()), "tail saw the append")
        r.equal(scanner.uniqueEventCount, 3, "partial trailing line is NOT consumed")
        let offsetAfterPartial = scanner.files[file.path]?.offset ?? 0
        r.equal(Int(offsetAfterPartial), fileSize(file) - partial.utf8.count, "offset stops before the partial line")

        // Finish the partial line: it is now picked up, exactly once.
        append(to: file, "\n")
        _ = scanner.tail(paths: [file.path], now: Date())
        r.equal(scanner.uniqueEventCount, 4, "completed line picked up")
        _ = scanner.tail(paths: [file.path], now: Date())
        r.equal(scanner.uniqueEventCount, 4, "re-tailing an unchanged file adds nothing")

        // Line handling at the mapping-window boundary, with a deliberately tiny window so the
        // growth and give-up paths are both exercised in a fraction of a second.
        let windowFile = dir.appendingPathComponent("window-probe.txt")
        let short = "short-line"
        let overWindow = String(repeating: "a", count: 700)        // bigger than the 256 B window, below the 1 KiB cap
        let overCap = String(repeating: "b", count: 9_000)         // bigger than the 1 KiB cap
        writeLines(to: windowFile, [short, overWindow, short + "2", overCap, short + "3"])
        var seen: [Int] = []
        let consumedEnd = LineReader.forEachLine(path: windowFile.path, from: 0,
                                                 upTo: UInt64(fileSize(windowFile)),
                                                 window: 256, maxWindow: 1024) { line in
            seen.append(line.count)
        }
        r.equal(consumedEnd, UInt64(fileSize(windowFile)), "window probe consumed the whole file")
        r.expect(seen.contains(short.count), "short lines read across windows")
        r.equal(seen.filter { $0 == short.count }.count, 1, "first short line read exactly once")
        r.expect(seen.contains(overWindow.count), "a line bigger than the window is read by growing it")
        r.expect(!seen.contains(overCap.count), "a line bigger than the growth cap is skipped, not looped on")
        r.equal(seen.filter { $0 == short.count + 1 }.count, 2, "parsing resynchronises after the skipped line")

        // A multi-megabyte user line must be skipped by the prefilter, not parsed.
        let huge = String(repeating: "x", count: 6_000_000)
        append(to: file, "{\"type\":\"user\",\"message\":{\"content\":\"\(huge)\"}}\n"
               + assistantLine(id: "t5", ts: base + 5, model: "claude-opus-5", output: 15) + "\n")
        _ = scanner.tail(paths: [file.path], now: Date())
        r.equal(scanner.uniqueEventCount, 5, "huge non-usage line skipped, next line still read")

        // Truncation: the file shrinks, so it must be re-read from zero without duplicating.
        writeLines(to: file, [assistantLine(id: "t9", ts: base + 6, model: "claude-opus-5", output: 99)])
        _ = scanner.tail(paths: [file.path], now: Date())
        r.equal(scanner.uniqueEventCount, 1, "truncated file re-read from scratch")
        r.equal(scanner.sortedEvents().first?.id ?? "", "t9", "only the new content survives")

        // Unknown keys and reordered fields must not upset the parser.
        let weird = """
        {"unknownTop":{"a":[1,2,3]},"type":"assistant","timestamp":"\(iso(base + 7))","sessionId":"zz","cwd":"/tmp/x","message":{"role":"assistant","mystery":true,"id":"t10","model":"claude-fable-5-1","content":[{"type":"text","text":"redacted"}],"usage":{"input_tokens":5,"output_tokens":6,"cache_creation_input_tokens":7,"cache_read_input_tokens":8,"cache_creation":{"ephemeral_5m_input_tokens":3,"ephemeral_1h_input_tokens":4},"brand_new_field":{"x":1}}}}
        """
        append(to: file, weird + "\n")
        _ = scanner.tail(paths: [file.path], now: Date())
        let t10 = scanner.sortedEvents().first { $0.id == "t10" }
        r.expect(t10 != nil, "line with unknown keys parsed")
        r.equal(t10?.input ?? 0, 5, "unknown keys: input")
        r.equal(t10?.cacheWrite1h ?? 0, 4, "unknown keys: 1h split")
        r.equal(t10?.cacheWrite5m ?? 0, 3, "unknown keys: 5m split")
        r.equal(t10?.model ?? "", "claude-fable-5-1", "unknown keys: model")

        // Numbers in a transcript line are data from another process. JSON allows `1e30`, and
        // `Int(1e30)` traps, so the parser has to clamp rather than convert. Negative counts are
        // nonsense and must read as zero, not as a negative token total.
        let absurd = """
        {"type":"assistant","timestamp":"\(iso(base + 8))","sessionId":"zz","cwd":"/tmp/x","message":{"id":"t11","model":"claude-opus-5","usage":{"input_tokens":1e30,"output_tokens":-5,"cache_creation_input_tokens":123456789012345678,"cache_read_input_tokens":7}}}
        """
        append(to: file, absurd + "\n")
        _ = scanner.tail(paths: [file.path], now: Date())
        guard let t11 = scanner.sortedEvents().first(where: { $0.id == "t11" }) else {
            r.expect(false, "absurd numeric line parsed without trapping"); return
        }
        r.expect(Double(t11.input) <= UsageEvent.maxTokenCount, "1e30 input_tokens is clamped, not converted")
        r.equal(t11.output, 0, "a negative output_tokens reads as zero")
        r.expect(Double(t11.cacheWriteTotal) <= UsageEvent.maxTokenCount, "a huge cache write is clamped")
        r.equal(t11.cacheRead, 7, "the sane fields of the same line are untouched")
        // And the aggregator must be able to add that event up without overflowing.
        let clampAgg = Aggregator(pricing: PricingResolver())
        let clampSnap = clampAgg.snapshot(events: scanner.sortedEvents(), now: Date(), planName: "", limits: [],
                                          liveStatus: .disabled, localStatus: LocalStatus())
        r.expect(clampSnap.today.tokens.total >= 0, "clamped counts still sum without trapping")

        // Lines that merely mention the words are not events.
        r.expect(!prefilterPasses("{\"type\":\"user\",\"text\":\"the assistant said hello, about usage and input tokens\"}"),
                 "prose mentioning assistant is prefiltered out")
        r.expect(prefilterPasses(assistantLine(id: "p", ts: base, model: "claude-opus-5", output: 1)),
                 "real assistant lines pass the prefilter")
    }

    // MARK: - 10 day file window / 11 day event eviction

    static func windowAndEviction(_ r: inout Runner) {
        r.section("age window and eviction")
        guard let dir = makeTempDir() else { r.expect(false, "temp dir"); return }
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        let day = 86_400.0

        // Two files: one touched today, one touched 20 days ago. Only the fresh one is scanned,
        // even though both sit in the tree.
        let fresh = dir.appendingPathComponent("aaaaaaaa-0000-0000-0000-000000000001.jsonl")
        let ancient = dir.appendingPathComponent("aaaaaaaa-0000-0000-0000-000000000002.jsonl")
        writeLines(to: fresh, [
            assistantLine(id: "recent", ts: now.timeIntervalSince1970 - 60, model: "claude-opus-5", output: 5),
            assistantLine(id: "old_event", ts: now.timeIntervalSince1970 - 12 * day, model: "claude-opus-5", output: 6),
            assistantLine(id: "edge_event", ts: now.timeIntervalSince1970 - 10.5 * day, model: "claude-opus-5", output: 7),
        ])
        writeLines(to: ancient, [assistantLine(id: "ancient", ts: now.timeIntervalSince1970 - 20 * day, model: "claude-opus-5", output: 8)])
        let longAgo = now.addingTimeInterval(-20 * day)
        try? FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: ancient.path)

        let scanner = TranscriptScanner(root: dir)
        r.equal(scanner.discover(now: now).count, 1, "only files modified in the last 10 days are considered")
        scanner.fullScan(now: now)
        let ids = Set(scanner.sortedEvents().map { $0.id })
        r.expect(!ids.contains("ancient"), "a file outside the 10 day window is never read")
        r.equal(scanner.uniqueEventCount, 3, "all three events of the fresh file are read")

        // Eviction keeps 11 days of events, so the 12 day old one goes and the 10.5 day one stays.
        r.expect(scanner.evict(now: now), "eviction reports that it dropped something")
        let after = Set(scanner.sortedEvents().map { $0.id })
        r.equal(after.count, 2, "one event evicted")
        r.expect(after.contains("recent"), "recent event kept")
        r.expect(after.contains("edge_event"), "10.5 day old event kept (inside the 11 day TTL)")
        r.expect(!after.contains("old_event"), "12 day old event evicted")
        r.expect(!scanner.evict(now: now), "a second eviction has nothing left to drop")

        // The evicted events must be gone from the per-file state too, or the cache would resurrect
        // them on the next launch.
        let reloaded = ScanCache.decode(ScanCache.encode(files: scanner.files))
        let cached = reloaded?[fresh.path]?.events.map { $0.id } ?? []
        r.equal(Set(cached), after, "the cache written after eviction has the same events")
    }

    // MARK: - Limits JSON

    static func limitsParsing(_ r: inout Runner) {
        r.section("limits JSON")
        let sample = """
        {"five_hour":{"utilization":41.5,"resets_at":"2026-09-21T01:50:00.324734+00:00"},
         "seven_day":{"utilization":0.0,"resets_at":"2026-09-27T20:00:00.324754+00:00"},
         "seven_day_opus":null,"seven_day_sonnet":null,
         "extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null},
         "some_future_key":{"nested":[1,2,3]},
         "limits":[
           {"kind":"session","group":"session","percent":41,"severity":"normal","resets_at":"2026-09-21T01:50:00.324734+00:00","scope":null,"is_active":true},
           {"kind":"weekly_all","group":"weekly","percent":17,"severity":"warning","resets_at":"2026-09-27T20:00:00.324754+00:00","scope":null,"is_active":false},
           {"kind":"weekly_scoped","group":"weekly","percent":4,"severity":"normal","resets_at":"2026-09-27T20:00:00.324922+00:00",
            "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}]}
        """
        guard let root = (try? JSONSerialization.jsonObject(with: Data(sample.utf8))) as? [String: Any] else {
            r.expect(false, "sample JSON did not parse"); return
        }
        let gauges = LimitsClient.parseLimits(root)
        r.equal(gauges.count, 3, "three gauges")
        r.equal(gauges[0].kind, .session, "session first")
        r.equal(gauges[0].id, "session", "session id")
        r.equal(gauges[0].title, "SESSION (5H)", "session title")
        r.close(gauges[0].percent, 41.5, 1e-9, "five_hour.utilization refines the integer percent")
        r.equal(gauges[0].windowSeconds ?? 0, 18_000, "session window")
        r.expect(gauges[0].isActive, "session is active")
        r.equal(gauges[0].severity, "normal", "session severity")
        r.equal(gauges[1].kind, .weeklyAll, "weekly all second")
        r.equal(gauges[1].title, "WEEK - ALL MODELS", "weekly title")
        r.close(gauges[1].percent, 17, 1e-9, "weekly percent kept (utilization is 0 and far away)")
        r.equal(gauges[1].windowSeconds ?? 0, 604_800, "weekly window")
        r.equal(gauges[1].severity, "warning", "severity passes through")
        r.equal(gauges[2].kind, .weeklyScoped, "scoped last")
        r.equal(gauges[2].id, "weekly_scoped:Fable", "scoped id")
        r.equal(gauges[2].title, "WEEK - FABLE", "scoped title")
        let reset = gauges[0].resetsAt.map { Int($0.timeIntervalSince1970) } ?? 0
        r.equal(reset, Int(ISO8601.epochSeconds("2026-09-21T01:50:00.324734+00:00") ?? 0), "6-digit resets_at parsed")

        // Fallback shape: no `limits` array at all.
        let fallback = """
        {"five_hour":{"utilization":12.5,"resets_at":"2026-09-21T01:50:00.324734+00:00"},
         "seven_day":{"utilization":33,"resets_at":"2026-09-27T20:00:00+00:00"},
         "seven_day_opus":{"utilization":7,"resets_at":null},
         "seven_day_sonnet":null}
        """
        guard let root2 = (try? JSONSerialization.jsonObject(with: Data(fallback.utf8))) as? [String: Any] else {
            r.expect(false, "fallback JSON did not parse"); return
        }
        let g2 = LimitsClient.parseLimits(root2)
        r.equal(g2.count, 3, "fallback gauge count")
        r.equal(g2[0].kind, .session, "fallback session")
        r.close(g2[0].percent, 12.5, 1e-9, "fallback session percent")
        r.equal(g2[1].kind, .weeklyAll, "fallback weekly")
        r.close(g2[1].percent, 33, 1e-9, "fallback weekly percent")
        r.equal(g2[2].kind, .weeklyScoped, "fallback scoped")
        r.equal(g2[2].title, "WEEK - OPUS", "fallback scoped title from the key")
        r.expect(g2[2].resetsAt == nil, "null resets_at tolerated")

        // Empty / unknown shapes.
        r.equal(LimitsClient.parseLimits([:]).count, 0, "empty object -> no gauges")
        r.equal(LimitsClient.parseLimits(["limits": []]).count, 0, "empty limits array -> no gauges")
        let odd: [String: Any] = ["limits": [["kind": "brand_new", "group": "weekly", "percent": 55]]]
        let g3 = LimitsClient.parseLimits(odd)
        r.equal(g3.count, 1, "unknown kind still produces a gauge")
        r.equal(g3[0].kind, .other, "unknown kind maps to .other")
        r.close(g3[0].percent, 55, 1e-9, "unknown kind percent")
        r.equal(g3[0].windowSeconds ?? 0, 604_800, "unknown kind window from group")

        // Every field of the `limits` array is optional (SPEC 4.3). When `percent` is absent or
        // null but the legacy object carries a utilisation, that utilisation IS the reading — a
        // gauge that silently shows 0 % because one key was missing is worse than no gauge.
        let missingPercent = """
        {"five_hour":{"utilization":41.5,"resets_at":"2026-09-21T01:50:00.324734+00:00"},
         "seven_day":{"utilization":63.25},
         "limits":[
           {"kind":"session","group":"session","resets_at":"2026-09-21T01:50:00.324734+00:00","is_active":true},
           {"kind":"weekly_all","group":"weekly","percent":null}]}
        """
        guard let root3 = (try? JSONSerialization.jsonObject(with: Data(missingPercent.utf8))) as? [String: Any] else {
            r.expect(false, "missing-percent JSON did not parse"); return
        }
        let g4 = LimitsClient.parseLimits(root3)
        r.equal(g4.count, 2, "two gauges when percent is missing")
        r.close(g4[0].percent, 41.5, 1e-9, "absent percent falls back to five_hour.utilization")
        r.close(g4[1].percent, 63.25, 1e-9, "null percent falls back to seven_day.utilization")

        // Out-of-range, non-numeric and hostile values.
        let hostile: [String: Any] = ["limits": [
            ["kind": "session", "group": "session", "percent": 250],
            ["kind": "weekly_all", "group": "weekly", "percent": -12],
            ["kind": "weekly_scoped", "group": "weekly", "percent": "not a number", "scope": NSNull()],
            "a bare string, not an object",
        ]]
        let g5 = LimitsClient.parseLimits(hostile)
        r.equal(g5.count, 3, "a non-object row is skipped, the rest survive")
        r.close(g5[0].percent, 100, 1e-9, "percent above 100 is clamped")
        r.close(g5[1].percent, 0, 1e-9, "negative percent is clamped")
        r.equal(g5[2].title, "WEEK - SCOPED", "a scoped limit with a null scope still gets a title")
        r.expect(g5[2].resetsAt == nil, "absent resets_at is nil")

        // A malformed reset time must not become a bogus date.
        let badReset: [String: Any] = ["limits": [["kind": "session", "group": "session", "percent": 5, "resets_at": "tomorrow-ish"]]]
        r.expect(LimitsClient.parseLimits(badReset).first?.resetsAt == nil, "unparseable resets_at is nil")

        // Backoff policy (SPEC 4.3: honour Retry-After, else exponential backoff to 15 min).
        r.section("live poll backoff")
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let withHeader = LivePollPolicy.schedule(outcome: .rateLimited(retryAt: t0.addingTimeInterval(229)), now: t0, previousBackoff: 0)
        r.close(withHeader.nextAllowedAt.timeIntervalSince(t0), 229, 1e-6, "Retry-After is honoured exactly")
        var backoff: TimeInterval = 0
        var waits: [TimeInterval] = []
        for _ in 0..<8 {
            let s = LivePollPolicy.schedule(outcome: .rateLimited(retryAt: nil), now: t0, previousBackoff: backoff)
            backoff = s.backoff
            waits.append(s.nextAllowedAt.timeIntervalSince(t0))
        }
        r.expect(waits[0] > 0, "a 429 without Retry-After still delays the next poll")
        r.expect(waits[1] > waits[0] && waits[2] > waits[1], "429 backoff grows")
        r.close(waits[7], 900, 1e-6, "429 backoff tops out at 15 minutes")
        r.expect(waits.allSatisfy { $0 <= 900 }, "429 backoff never exceeds 15 minutes")

        var errBackoff: TimeInterval = 0
        var errWaits: [TimeInterval] = []
        for _ in 0..<8 {
            let s = LivePollPolicy.schedule(outcome: .failure("offline"), now: t0, previousBackoff: errBackoff)
            errBackoff = s.backoff
            errWaits.append(s.nextAllowedAt.timeIntervalSince(t0))
        }
        r.expect(errWaits[1] > errWaits[0], "error backoff grows")
        r.close(errWaits[7], 900, 1e-6, "error backoff tops out at 15 minutes")

        let recovered = LivePollPolicy.schedule(outcome: .success(planName: "", limits: []), now: t0, previousBackoff: 600)
        r.close(recovered.backoff, 0, 1e-9, "a success clears the backoff")
        r.expect(recovered.nextAllowedAt <= t0, "a success does not hold the next poll back")
        let auth = LivePollPolicy.schedule(outcome: .authExpired, now: t0, previousBackoff: 600)
        r.expect(auth.nextAllowedAt <= t0, "auth expiry retries on the normal schedule, not a backoff")

        r.section("limits JSON")
        // Credential parsing never exposes the token in a description.
        let credJSON = Data("""
        {"claudeAiOauth":{"accessToken":"sk-not-a-real-token","expiresAt":32503680000000,"subscriptionType":"max","rateLimitTier":"default_claude_max_20x","scopes":["user:inference"]}}
        """.utf8)
        guard let cred = CredentialReader.parse(credJSON) else { r.expect(false, "credential parse"); return }
        r.equal(cred.rateLimitTier ?? "", "default_claude_max_20x", "tier")
        r.expect(cred.expiresAt != nil && !cred.isExpired, "far-future expiry is not expired")
        r.expect(!cred.description.contains("sk-not-a-real-token"), "token never appears in description")
        let expired = CredentialReader.parse(Data("{\"claudeAiOauth\":{\"accessToken\":\"x\",\"expiresAt\":1000}}".utf8))
        r.expect(expired?.isExpired == true, "past expiry detected")
    }

    static func planNames(_ r: inout Runner) {
        r.section("plan names")
        r.equal(LimitsClient.planName(tier: "default_claude_max_20x", subscription: "max"), "MAX 20X", "max 20x")
        r.equal(LimitsClient.planName(tier: "default_claude_max_5x", subscription: "max"), "MAX 5X", "max 5x")
        r.equal(LimitsClient.planName(tier: "default_claude_pro", subscription: "pro"), "PRO", "pro")
        r.equal(LimitsClient.planName(tier: "pro", subscription: nil), "PRO", "bare pro")
        r.equal(LimitsClient.planName(tier: nil, subscription: "max"), "MAX", "subscription fallback")
        r.equal(LimitsClient.planName(tier: nil, subscription: nil), "", "nothing known")
    }

    // MARK: - Cache round trip

    static func cacheRoundTrip(_ r: inout Runner) {
        r.section("scan cache")
        var f = ScannedFile(path: "/tmp/a \"quoted\"/b.jsonl", sessionID: "sess-1")
        f.size = 4096
        f.mtime = 1_789_940_232.25
        f.inode = 987_654
        f.offset = 4000
        f.events = [
            makeEvent(id: "c1", ts: 1_789_940_000.125, model: "claude-opus-5", input: 1, output: 2, writeTotal: 3, write1h: 1, read: 4),
            makeEvent(id: "c2", ts: 1_789_940_100.5, model: "claude-fable-5-1", input: 10, output: 20, writeTotal: 30, write1h: 0, read: 40),
        ]
        let data = ScanCache.encode(files: [f.path: f])
        r.expect((try? JSONSerialization.jsonObject(with: data)) != nil, "cache file is valid JSON")
        guard let back = ScanCache.decode(data), let g = back[f.path] else {
            r.expect(false, "cache decode"); return
        }
        r.equal(g.size, f.size, "size")
        r.close(g.mtime, f.mtime, 1e-9, "mtime")
        r.equal(g.inode, f.inode, "inode")
        r.equal(g.offset, f.offset, "offset")
        r.equal(g.events.count, 2, "event count")
        r.equal(g.events[0].id, "c1", "event id")
        r.close(g.events[0].timestamp, 1_789_940_000.125, 1e-3, "event timestamp")
        r.equal(g.events[1].model, "claude-fable-5-1", "event model")
        r.equal(g.events[0].cacheWrite1h, 1, "1h split survives")
        r.equal(g.events[1].cacheRead, 40, "cache read survives")

        // Strings with escapes and non-ASCII survive the hand-rolled reader.
        var odd = ScannedFile(path: "/tmp/tab\tnew\nline/ünïcode \"q\"/z.jsonl", sessionID: "s")
        odd.events = [makeEvent(id: "e\\1", ts: 1_000_000.5, model: "claude-opus-5", input: 1, output: 2, writeTotal: 3, write1h: 1, read: 4)]
        guard let oddBack = ScanCache.decode(ScanCache.encode(files: [odd.path: odd]))?[odd.path] else {
            r.expect(false, "escaped strings round trip"); return
        }
        r.equal(oddBack.path, odd.path, "escapes and unicode in paths")
        r.equal(oddBack.events.first?.id ?? "", "e\\1", "escaped event id")

        // Whitespace and unknown keys (a cache written by a newer build) are tolerated.
        let padded = Data("""
        { "v" : 1 , "extra" : {"a":[1,2,{"b":null}]} , "strings" : [ "sess" , "claude-opus-5" , "/tmp" ] ,
          "files" : [ { "p" : "/tmp/x.jsonl" , "sz" : 10 , "mt" : 1.5 , "in" : 2 , "of" : 10 , "newkey" : true ,
                        "e" : [ [ 1500 , 0 , 1 , 2 , 1 , 2 , 3 , 0 , 4 , "m1" ] ] } ] }
        """.utf8)
        guard let tolerant = ScanCache.decode(padded)?["/tmp/x.jsonl"] else {
            r.expect(false, "tolerant decode"); return
        }
        r.equal(tolerant.offset, 10, "whitespace-heavy cache decoded")
        r.equal(tolerant.events.count, 1, "event decoded")
        r.close(tolerant.events[0].timestamp, 1.5, 1e-9, "millisecond timestamp")
        r.equal(tolerant.events[0].model, "claude-opus-5", "interned model resolved")
        r.equal(tolerant.events[0].cwd, "/tmp", "interned cwd resolved")

        // A corrupt or differently versioned file is ignored rather than trusted.
        r.expect(ScanCache.decode(Data("{".utf8)) == nil, "truncated cache rejected")
        r.expect(ScanCache.decode(Data("{\"v\":999,\"strings\":[],\"files\":[]}".utf8)) == nil, "wrong version rejected")
        r.expect(ScanCache.decode(Data("{\"v\":1,\"strings\":[],\"files\":[{\"p\":\"/a\",\"e\":[[1,2]]}]}".utf8)) == nil, "short event row rejected")
        r.expect(ScanCache.decode(Data("not json at all".utf8)) == nil, "garbage rejected")
        r.expect(ScanCache.decode(Data()) == nil, "empty file rejected")
        let whole = ScanCache.encode(files: [f.path: f])
        r.expect(ScanCache.decode(Data(whole.prefix(whole.count / 2))) == nil, "half-written cache rejected")
        r.expect(ScanCache.decode(Data(whole.prefix(whole.count - 3))) == nil, "cache cut short at the end rejected")
    }

    // MARK: - Hostile cache files
    //
    // The cache lives in Application Support, where a half-written file, a disk error or an older
    // build can leave anything at all. Every one of these must be *rejected*, never trusted and
    // above all never trapped on: `UInt64(Double)` and `Int(Double)` trap on infinity and NaN, and
    // a JSON number is allowed to be arbitrarily long.

    static func hostileCache(_ r: inout Runner) {
        r.section("hostile cache files")

        func decodeMustNotTrap(_ text: String, _ what: String) -> [String: ScannedFile]? {
            let out = ScanCache.decode(Data(text.utf8))
            r.checks += 1              // reaching this line at all is the check
            return out
        }

        // Infinity through an exponent.
        _ = decodeMustNotTrap("{\"v\":1,\"strings\":[],\"files\":[{\"p\":\"/a\",\"sz\":1e999,\"mt\":0,\"in\":1,\"of\":0,\"e\":[]}]}",
                              "huge size does not trap")
        // NaN: 0 * 10^inf.
        _ = decodeMustNotTrap("{\"v\":1,\"strings\":[],\"files\":[{\"p\":\"/a\",\"sz\":0e999,\"mt\":0,\"in\":1,\"of\":0,\"e\":[]}]}",
                              "NaN size does not trap")
        // Negative offsets.
        let negative = decodeMustNotTrap("{\"v\":1,\"strings\":[],\"files\":[{\"p\":\"/a\",\"sz\":10,\"mt\":0,\"in\":1,\"of\":-5,\"e\":[]}]}",
                                         "negative offset does not trap")
        r.equal(negative?["/a"]?.offset ?? 99, 0, "negative offset clamped to zero")
        // A 400 digit integer.
        let longDigits = String(repeating: "9", count: 400)
        _ = decodeMustNotTrap("{\"v\":1,\"strings\":[],\"files\":[{\"p\":\"/a\",\"sz\":\(longDigits),\"mt\":0,\"in\":1,\"of\":0,\"e\":[]}]}",
                              "400-digit size does not trap")
        // Out-of-range numbers inside an event row.
        _ = decodeMustNotTrap("{\"v\":1,\"strings\":[\"s\"],\"files\":[{\"p\":\"/a\",\"sz\":10,\"mt\":0,\"in\":1,\"of\":0,\"e\":[[1e999,0,0,0,1e999,2,3,0,4,\"m\"]]}]}",
                              "huge event numbers do not trap")
        _ = decodeMustNotTrap("{\"v\":1,\"strings\":[\"s\"],\"files\":[{\"p\":\"/a\",\"sz\":10,\"mt\":0,\"in\":1,\"of\":0,\"e\":[[0e999,0,0,0,1,2,3,0,4,\"m\"]]}]}",
                              "NaN event timestamp does not trap")
        // A string-table index that is out of range must not trap either.
        let badIndex = decodeMustNotTrap("{\"v\":1,\"strings\":[],\"files\":[{\"p\":\"/a\",\"sz\":10,\"mt\":0,\"in\":1,\"of\":0,\"e\":[[1500,7,8,9,1,2,3,0,4,\"m\"]]}]}",
                                         "out-of-range string index does not trap")
        r.equal(badIndex?["/a"]?.events.first?.model ?? "-", "", "out-of-range string index reads as empty")

        // A cache whose numbers are survivable must still produce sane state.
        if let ok = ScanCache.decode(Data("{\"v\":1,\"strings\":[\"s\"],\"files\":[{\"p\":\"/a\",\"sz\":10,\"mt\":1.5,\"in\":3,\"of\":10,\"e\":[]}]}".utf8)) {
            r.equal(ok["/a"]?.offset ?? 0, 10, "well-formed hostile-shaped cache still decodes")
        } else {
            r.expect(false, "well-formed cache rejected")
        }

        // Every event a decoded cache produces must be usable by the aggregator without trapping.
        let agg = Aggregator(pricing: PricingResolver())
        let hostileEventCache = "{\"v\":1,\"strings\":[\"s\",\"m\",\"/c\"],\"files\":[{\"p\":\"/a\",\"sz\":10,\"mt\":0,\"in\":1,\"of\":0,\"e\":[[1e999,0,1,2,1,2,3,0,4,\"m\"]]}]}"
        if let files = ScanCache.decode(Data(hostileEventCache.utf8)) {
            let events = files.values.flatMap { $0.events }.sorted { $0.timestamp < $1.timestamp }
            let snap = agg.snapshot(events: events, now: Date(), planName: "", limits: [],
                                    liveStatus: .disabled, localStatus: LocalStatus())
            r.equal(snap.fine.count, UsageSnapshot.fineBucketCount, "aggregator survives a hostile cached event")
        }
    }

    // MARK: - Local days, DST

    /// `days` are *local calendar* days, so on a DST boundary one of them is 23 or 25 hours long and
    /// every start must still be local midnight. Anything that quietly used 86 400 s steps would
    /// misplace a whole day's events twice a year.
    static func localTimeAndDST(_ r: inout Runner) {
        r.section("local days and DST")
        let savedZone = NSTimeZone.default
        defer { NSTimeZone.default = savedZone }
        guard let zone = TimeZone(identifier: "America/New_York") else {
            r.expect(false, "test timezone unavailable"); return
        }
        NSTimeZone.default = zone

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        guard Calendar.current.timeZone.identifier == zone.identifier else {
            r.expect(false, "Calendar.current did not follow NSTimeZone.default"); return
        }

        // 2026-11-01 is the US fall-back: that local day is 25 hours long.
        guard let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12)) else {
            r.expect(false, "date components"); return
        }
        let agg = Aggregator(pricing: PricingResolver())
        let snap = agg.snapshot(events: [], now: now, planName: "", limits: [], liveStatus: .disabled,
                                localStatus: LocalStatus())
        r.equal(snap.days.count, UsageSnapshot.dayBucketCount, "day count across DST")
        for b in snap.days {
            r.equal(b.start, cal.startOfDay(for: b.start), "day bucket starts at local midnight")
        }
        for k in 1..<snap.days.count {
            let gap = snap.days[k].start.timeIntervalSince(snap.days[k - 1].start)
            r.close(gap, snap.days[k - 1].duration, 1e-6, "day duration matches the gap to the next day")
        }
        let fallBack = snap.days.first { cal.component(.day, from: $0.start) == 1 && cal.component(.month, from: $0.start) == 11 }
        r.close(fallBack?.duration ?? 0, 25 * 3600, 1e-6, "the fall-back day is 25 hours long")
        r.equal(snap.today.start, cal.startOfDay(for: now), "today starts at local midnight")

        // An event at local midnight belongs to the new day; one second earlier to the old one.
        let midnight = cal.startOfDay(for: now).timeIntervalSince1970
        let events = [
            makeEvent(id: "before", ts: midnight - 1, model: "claude-opus-5", input: 1, output: 1, writeTotal: 0, write1h: 0, read: 0),
            makeEvent(id: "after", ts: midnight, model: "claude-opus-5", input: 1, output: 1, writeTotal: 0, write1h: 0, read: 0),
        ]
        let placed = agg.snapshot(events: events, now: now, planName: "", limits: [], liveStatus: .disabled,
                                  localStatus: LocalStatus())
        r.equal(placed.today.messages, 1, "only the event at/after local midnight is in today")
        r.equal(placed.days[placed.days.count - 2].messages, 1, "the event one second earlier is in yesterday")
        r.equal(placed.sessionsToday.count, 1, "sessionsToday uses the same local-midnight boundary")

        // A half-hour-offset zone must not shift the day boundary either.
        if let kolkata = TimeZone(identifier: "Asia/Kolkata") {
            NSTimeZone.default = kolkata
            var kcal = Calendar(identifier: .gregorian)
            kcal.timeZone = kolkata
            let agg2 = Aggregator(pricing: PricingResolver())
            let snap2 = agg2.snapshot(events: [], now: now, planName: "", limits: [], liveStatus: .disabled,
                                      localStatus: LocalStatus())
            r.equal(snap2.today.start, kcal.startOfDay(for: now), "half-hour zone: today starts at local midnight")
            r.close(snap2.today.duration, 86_400, 1e-6, "half-hour zone: ordinary day is 24 h")
        }
    }

    // MARK: - Clock skew

    /// Transcripts are written by other processes and can carry timestamps from the future (a laptop
    /// that was asleep, a clock that stepped). Nothing may trap, and a future event must not be
    /// counted as "now".
    static func clockSkew(_ r: inout Runner) {
        r.section("clock skew")
        let agg = Aggregator(pricing: PricingResolver())
        let now = Date(timeIntervalSince1970: 1_789_940_232)
        let events = [
            makeEvent(id: "ancient", ts: 0, model: "claude-opus-5", input: 1, output: 1, writeTotal: 0, write1h: 0, read: 0),
            makeEvent(id: "now", ts: now.timeIntervalSince1970 - 10, model: "claude-opus-5", input: 1, output: 1, writeTotal: 0, write1h: 0, read: 0),
            makeEvent(id: "year9999", ts: 253_402_300_799, model: "claude-opus-5", input: 1, output: 1, writeTotal: 0, write1h: 0, read: 0),
        ].sorted { $0.timestamp < $1.timestamp }
        let snap = agg.snapshot(events: events, now: now, planName: "", limits: [], liveStatus: .disabled,
                                localStatus: LocalStatus())
        r.equal(snap.fine.count, UsageSnapshot.fineBucketCount, "skewed events do not break the fine grid")
        r.equal(snap.days.reduce(0) { $0 + $1.messages }, 1, "only the in-window event lands in a day bucket")
        r.equal(snap.fine.reduce(0) { $0 + $1.messages }, 1, "only the in-window event lands in a fine bucket")

        // A timestamp far in the future must not be published as "the last event", or the UI shows a
        // negative age for ever and the poll schedule thinks the machine is permanently busy.
        r.expect((snap.lastEventAt?.timeIntervalSince1970 ?? 0) <= now.timeIntervalSince1970 + 120,
                 "lastEventAt is not dragged into the far future")
        r.expect(snap.burnTokensPerMin >= 0, "burn rate stays finite")

        // An ISO-8601 year far outside anything real still parses to a finite number.
        let far = ISO8601.epochSeconds("9999-12-31T23:59:59.999Z")
        r.expect((far ?? 0).isFinite, "year 9999 parses finitely")
    }

    // MARK: - Activity windows

    static func activityWindows(_ r: inout Runner) {
        r.section("activity windows")
        let agg = Aggregator(pricing: PricingResolver())
        let now = Date()
        let t = now.timeIntervalSince1970
        var events: [UsageEvent] = []
        // Three sessions: one 10 s ago, one 119 s ago, one 200 s ago.
        for (i, back) in [10.0, 119.0, 200.0].enumerated() {
            var e = makeEvent(id: "a\(i)", ts: t - back, model: "claude-opus-5", input: 10, output: 20, writeTotal: 30, write1h: 0, read: 1000)
            e.sessionID = "sess-\(i)"
            events.append(e)
        }
        events.sort { $0.timestamp < $1.timestamp }
        let snap = agg.snapshot(events: events, now: now, planName: "", limits: [], liveStatus: .disabled,
                                localStatus: LocalStatus())
        // (Only valid when "now" is more than 200 s past local midnight, which it is except in a
        // three minute window each night; skip the assertion there rather than flake.)
        let sinceMidnight = t - Calendar.current.startOfDay(for: now).timeIntervalSince1970
        if sinceMidnight > 300 {
            r.equal(snap.sessionsToday.count, 3, "three sessions today")
            r.equal(snap.activeSessionCount, 2, "active = activity in the last 2 minutes")
            r.equal(snap.sessionsToday.first?.id ?? "", "sess-0", "most recent activity first")
            r.expect(snap.sessionsToday.first?.isActive == true, "the newest session is active")
            r.expect(snap.sessionsToday.last?.isActive == false, "the 200 s old session is not active")
            // Burn counts fresh tokens only, over five minutes.
            r.close(snap.burnTokensPerMin, Double(3 * 60) / 5, 1e-6, "burn excludes cache reads")
        }
    }

    // MARK: - A full rescan must behave exactly like a tail

    /// `tail()` is exercised above; the 30 s safety rescan takes the other path through
    /// `fullScan`/`prepare`, and it has to reach the same state — in particular it must not re-read
    /// a line it already consumed, and it must pick up a line that was partial last time.
    static func rescanAfterPartialLine(_ r: inout Runner) {
        r.section("full rescan vs tail")
        guard let dir = makeTempDir() else { r.expect(false, "temp dir"); return }
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("66666666-6666-6666-6666-666666666666.jsonl")
        let base = Date().timeIntervalSince1970 - 120

        writeLines(to: file, [assistantLine(id: "f1", ts: base, model: "claude-opus-5", output: 1)])
        let scanner = TranscriptScanner(root: dir)
        scanner.fullScan(now: Date())
        r.equal(scanner.uniqueEventCount, 1, "first pass")

        // Append a complete line and a partial one, then rescan (not tail).
        let partial = assistantLine(id: "f3", ts: base + 2, model: "claude-opus-5", output: 3)
        append(to: file, assistantLine(id: "f2", ts: base + 1, model: "claude-opus-5", output: 2) + "\n" + partial)
        scanner.fullScan(now: Date())
        r.equal(scanner.uniqueEventCount, 2, "rescan takes the complete line and leaves the partial one")
        r.equal(Int(scanner.files[file.path]?.offset ?? 0), fileSize(file) - partial.utf8.count,
                "rescan offset stops before the partial line")

        // Complete it; a rescan must pick it up exactly once.
        append(to: file, "\n")
        scanner.fullScan(now: Date())
        r.equal(scanner.uniqueEventCount, 3, "rescan picks the completed line up")
        scanner.fullScan(now: Date())
        r.equal(scanner.uniqueEventCount, 3, "a further rescan adds nothing")
        r.equal(scanner.sortedEvents().filter { $0.id == "f3" }.count, 1, "no duplicate event from the rescan")

        // Truncation seen by a rescan rather than a tail.
        writeLines(to: file, [assistantLine(id: "f9", ts: base + 3, model: "claude-opus-5", output: 9)])
        scanner.fullScan(now: Date())
        r.equal(scanner.uniqueEventCount, 1, "rescan detects truncation and re-reads from zero")
        r.equal(scanner.sortedEvents().first?.id ?? "", "f9", "only the new content survives a rescan")

        // A file that leaves the 10 day window must take its events with it.
        let stamp = Date().addingTimeInterval(-20 * 86_400)
        try? FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
        scanner.fullScan(now: Date())
        r.equal(scanner.uniqueEventCount, 0, "a file that ages out of the window loses its events")
    }

    // MARK: - Attribution determinism

    /// The same event id can appear in two files (a resumed or forked session copies old lines).
    /// Whichever session it is attributed to, a cold scan and a warm cache load must agree, or the
    /// Sessions list changes shape depending on how the app happened to start.
    static func attributionDeterminism(_ r: inout Runner) {
        r.section("attribution determinism")
        guard let dir = makeTempDir() else { r.expect(false, "temp dir"); return }
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = dir.appendingPathComponent("aaaaaaaa-1111-1111-1111-111111111111.jsonl")
        let new = dir.appendingPathComponent("bbbbbbbb-2222-2222-2222-222222222222.jsonl")
        let base = Date().timeIntervalSince1970 - 600
        writeLines(to: old, [assistantLine(id: "shared_1", ts: base, model: "claude-opus-5", output: 10)])
        // The resumed file copies the old line and adds its own.
        writeLines(to: new, [
            assistantLine(id: "shared_1", ts: base, model: "claude-opus-5", output: 10),
            assistantLine(id: "fresh_1", ts: base + 5, model: "claude-opus-5", output: 20),
        ])
        // Make the resumed file clearly the newer one.
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-300)], ofItemAtPath: old.path)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: new.path)

        let cold = TranscriptScanner(root: dir)
        cold.fullScan(now: Date())
        r.equal(cold.uniqueEventCount, 2, "the copied line is deduped across files")
        let coldSession = cold.sortedEvents().first { $0.id == "shared_1" }?.sessionID ?? ""

        let cacheURL = dir.appendingPathComponent("scan-cache.json")
        try? ScanCache.encode(files: cold.files).write(to: cacheURL)
        let warm = TranscriptScanner(root: dir)
        r.expect(warm.loadCache(from: cacheURL), "cache round trip loads")
        let warmSession = warm.sortedEvents().first { $0.id == "shared_1" }?.sessionID ?? ""
        r.equal(warmSession, coldSession, "cold scan and warm cache agree on the session of a duplicated event")
        r.equal(coldSession, "bbbbbbbb-2222-2222-2222-222222222222", "the newest transcript owns a duplicated event")
        r.equal(warm.uniqueEventCount, 2, "warm load keeps the dedup")

        // The same thing again, but with the newest transcript large enough that the cold scan
        // defers it behind the quick files. The read order then no longer matches the newest-first
        // order, and a cold start must still agree with a warm one.
        guard let dir2 = makeTempDir() else { r.expect(false, "temp dir"); return }
        defer { try? FileManager.default.removeItem(at: dir2) }
        let savedThreshold = TranscriptScanner.deferredFileBytes
        defer { TranscriptScanner.deferredFileBytes = savedThreshold }
        TranscriptScanner.deferredFileBytes = 2_048

        let light = dir2.appendingPathComponent("cccccccc-3333-3333-3333-333333333333.jsonl")
        let heavy = dir2.appendingPathComponent("dddddddd-4444-4444-4444-444444444444.jsonl")
        writeLines(to: light, [assistantLine(id: "shared_2", ts: base, model: "claude-opus-5", output: 10)])
        var heavyLines = [assistantLine(id: "shared_2", ts: base, model: "claude-opus-5", output: 10)]
        // Padding on `user` lines, which the prefilter rejects — this only has to make the file big.
        for k in 0..<12 { heavyLines.append("{\"type\":\"user\",\"pad\":\"\(String(repeating: "z", count: 512))\",\"k\":\(k)}") }
        writeLines(to: heavy, heavyLines)
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-300)], ofItemAtPath: light.path)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: heavy.path)
        r.expect(UInt64(fileSize(heavy)) > TranscriptScanner.deferredFileBytes, "the heavy fixture is over the deferral threshold")

        let cold2 = TranscriptScanner(root: dir2)
        cold2.fullScan(now: Date())
        let coldSession2 = cold2.sortedEvents().first { $0.id == "shared_2" }?.sessionID ?? ""
        let cacheURL2 = dir2.appendingPathComponent("scan-cache.json")
        try? ScanCache.encode(files: cold2.files).write(to: cacheURL2)
        let warm2 = TranscriptScanner(root: dir2)
        r.expect(warm2.loadCache(from: cacheURL2), "deferred-file cache loads")
        let warmSession2 = warm2.sortedEvents().first { $0.id == "shared_2" }?.sessionID ?? ""
        r.equal(coldSession2, "dddddddd-4444-4444-4444-444444444444",
                "a deferred newest file still owns the duplicated event on a cold scan")
        r.equal(warmSession2, coldSession2, "deferred cold scan and warm cache agree")
    }

    // MARK: - The parallel read path

    /// A cold scan reads files in widening batches through `concurrentPerform`, so the batch path
    /// only runs at all once there are more than a couple of files. This fixture is big enough to
    /// exercise it (and, under Thread Sanitizer, to prove the shared state stays on the scan queue).
    static func parallelScan(_ r: inout Runner) {
        r.section("parallel cold scan")
        guard let dir = makeTempDir() else { r.expect(false, "temp dir"); return }
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = Date().timeIntervalSince1970 - 3600
        let fileCount = 24
        for f in 0..<fileCount {
            let url = dir.appendingPathComponent(String(format: "%08x-0000-0000-0000-000000000000.jsonl", f))
            var lines: [String] = []
            for k in 0..<8 {
                // Every file repeats one shared id, so dedup has to hold across the batches too.
                lines.append(assistantLine(id: "shared_all", ts: base, model: "claude-opus-5", output: 5))
                lines.append(assistantLine(id: "f\(f)_e\(k)", ts: base + Double(f * 8 + k), model: "claude-opus-5", output: k))
                lines.append("{\"type\":\"user\",\"pad\":\"\(String(repeating: "q", count: 200))\"}")
            }
            writeLines(to: url, lines)
        }
        let scanner = TranscriptScanner(root: dir)
        scanner.fullScan(now: Date())
        r.equal(scanner.uniqueEventCount, fileCount * 8 + 1, "every file's events survive the parallel batches")
        r.equal(scanner.sortedEvents().filter { $0.id == "shared_all" }.count, 1, "dedup holds across batches")
        let sorted = scanner.sortedEvents()
        r.expect(zip(sorted, sorted.dropFirst()).allSatisfy { $0.timestamp <= $1.timestamp }, "events come back sorted")
        r.equal(scanner.stats.filesParsed, fileCount, "every file was read exactly once")
        // A second pass must read nothing and change nothing.
        let before = scanner.stats.bytesRead
        scanner.fullScan(now: Date())
        r.equal(scanner.stats.bytesRead, before, "a rescan of an unchanged tree reads no bytes")
        r.equal(scanner.uniqueEventCount, fileCount * 8 + 1, "a rescan does not duplicate anything")
    }

    // MARK: - The provider itself

    /// Drives a real `LiveUsageProvider` over a scratch transcript tree: the publishing contract,
    /// live file pickup, pause and resume, `stop()`, and the warm start. The live source is off
    /// throughout, so no credential is read and nothing goes near the network.
    static func providerLifecycle(_ r: inout Runner) {
        r.section("provider lifecycle")
        guard let tree = makeTempDir(), let support = makeTempDir() else {
            r.expect(false, "temp dirs"); return
        }
        defer {
            try? FileManager.default.removeItem(at: tree)
            try? FileManager.default.removeItem(at: support)
        }
        let cacheURL = support.appendingPathComponent("scan-cache.json")
        let file = tree.appendingPathComponent("77777777-7777-7777-7777-777777777777.jsonl")
        let now = Date().timeIntervalSince1970
        writeLines(to: file, [
            assistantLine(id: "pl1", ts: now, model: "claude-opus-5", output: 10),
            assistantLine(id: "pl2", ts: now, model: "claude-opus-5", output: 20),
        ])

        let provider = LiveUsageProvider(root: tree, cacheURL: cacheURL,
                                         pricingURL: support.appendingPathComponent("pricing.json"))
        provider.isLiveEnabled = false
        var publishes = 0
        var latest: UsageSnapshot?
        var offMainThread = 0
        provider.onChange = { snap in
            publishes += 1
            latest = snap
            if !Thread.isMainThread { offMainThread += 1 }
        }
        provider.start()

        r.expect(waitUntil(6) { latest?.today.messages ?? 0 >= 2 }, "the first scan publishes the events on disk")
        r.equal(offMainThread, 0, "every onChange so far arrived on the main thread")
        r.equal(latest?.today.messages ?? -1, 2, "two events after the first scan")
        r.equal(latest?.fine.count ?? 0, UsageSnapshot.fineBucketCount, "published snapshot is fully shaped")
        r.expect(latest?.liveStatus == .disabled, "live disabled reports .disabled")
        r.expect(latest?.limits.isEmpty ?? false, "live disabled publishes no gauges")

        // The provider must keep publishing while running even with no new data, because time
        // alone moves the buckets. The contract is one per second; the margin here is wide so the
        // check still means something under Thread Sanitizer on a loaded machine. The real rate is
        // measured with `usage-dump --watch` against live data.
        let before = publishes
        _ = waitUntil(4.0) { false }
        r.expect(publishes >= before + 2, "keeps publishing with no new data (got \(publishes - before) in 4 s)")

        // A file change is picked up and published without a rescan being asked for.
        append(to: file, assistantLine(id: "pl3", ts: Date().timeIntervalSince1970, model: "claude-opus-5", output: 30) + "\n")
        r.expect(waitUntil(6) { latest?.today.messages ?? 0 >= 3 }, "a live append is picked up by the watcher")

        // Paused: no further snapshots, and work done while paused is not lost.
        provider.isPaused = true
        _ = waitUntil(0.8) { false }
        let whilePaused = publishes
        append(to: file, assistantLine(id: "pl4", ts: Date().timeIntervalSince1970, model: "claude-opus-5", output: 40) + "\n")
        _ = waitUntil(1.5) { false }
        r.equal(publishes, whilePaused, "a paused provider publishes nothing")
        r.equal(latest?.today.messages ?? -1, 3, "a paused provider keeps the last snapshot")

        provider.isPaused = false
        r.expect(waitUntil(6) { latest?.today.messages ?? 0 >= 4 },
                 "resuming picks up what changed while paused")

        // Stopping is final: nothing may be published afterwards.
        provider.stop()
        let afterStop = publishes
        _ = waitUntil(1.2) { false }
        r.equal(publishes, afterStop, "no snapshot is published after stop()")
        r.equal(provider.snapshot.today.messages, 4, "the last snapshot survives stop()")

        // stop() flushes the cache, so the next launch is warm.
        r.expect(FileManager.default.fileExists(atPath: cacheURL.path), "stop() leaves a scan cache behind")
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { ScanCache.decode($0) }
        r.equal(cached?.values.reduce(0) { $0 + $1.events.count } ?? -1, 4, "the cache holds every event")

        let warm = LiveUsageProvider(root: tree, cacheURL: cacheURL,
                                     pricingURL: support.appendingPathComponent("pricing.json"))
        warm.isLiveEnabled = false
        var warmSnap: UsageSnapshot?
        warm.onChange = { warmSnap = $0 }
        warm.start()
        r.expect(waitUntil(6) { warmSnap?.today.messages ?? 0 >= 4 }, "a warm start republishes every event")
        r.expect(warm.diagnostics.loadedFromCache, "the warm start really came from the cache")
        r.equal(offMainThread, 0, "every onChange arrived on the main thread")
        warm.stop()
    }

    /// Spins the main run loop until `condition` holds or `timeout` elapses. Snapshots are handed to
    /// the main thread, so a test that merely slept would never see one.
    @discardableResult
    static func waitUntil(_ timeout: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    // MARK: - Fixtures

    static func makeEvent(id: String, ts: Double, model: String, input: Int, output: Int,
                          writeTotal: Int, write1h: Int, read: Int) -> UsageEvent {
        UsageEvent(id: id, timestamp: ts, sessionID: "session-a", cwd: "/tmp/project",
                   model: model, input: input, output: output,
                   cacheWriteTotal: writeTotal, cacheWrite1h: write1h, cacheRead: read)
    }

    static func iso(_ epoch: Double) -> String {
        let whole = floor(epoch)
        let ms = Int(((epoch - whole) * 1000).rounded())
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: whole)) + String(format: ".%03dZ", ms)
    }

    /// A realistic transcript line. Content is a placeholder — the parser must never look at it.
    static func assistantLine(id: String, ts: Double, model: String, output: Int, sessionID: String = "ignored-session") -> String {
        """
        {"parentUuid":"p","isSidechain":false,"message":{"model":"\(model)","id":"\(id)","type":"message","role":"assistant","content":[{"type":"text","text":"placeholder"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"cache_creation_input_tokens":800,"cache_read_input_tokens":24000,"output_tokens":\(output),"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":800,"ephemeral_5m_input_tokens":0}}},"requestId":"req","type":"assistant","uuid":"u","timestamp":"\(iso(ts))","sessionId":"\(sessionID)","cwd":"/tmp/project","version":"9.9.9"}
        """
    }

    static func makeTempDir() -> URL? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tokenamp-selftest-\(UInt32.random(in: 0...UInt32.max))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            // The scanner resolves its root, so the fixtures have to live at resolved paths too.
            return URL(fileURLWithPath: TokenampPaths.realPath(url.path), isDirectory: true)
        } catch {
            return nil
        }
    }

    static func writeLines(to url: URL, _ lines: [String]) {
        let text = lines.joined(separator: "\n") + "\n"
        try? Data(text.utf8).write(to: url)
    }

    static func append(to url: URL, _ text: String) {
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        h.seekToEndOfFile()
        h.write(Data(text.utf8))
        try? h.close()
    }

    static func fileSize(_ url: URL) -> Int {
        guard let values = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = values[.size] as? NSNumber else { return -1 }
        return size.intValue
    }

    static func prefilterPasses(_ s: String) -> Bool {
        Array(s.utf8).withUnsafeBytes { TranscriptLineParser.passesPrefilter($0) }
    }
}
