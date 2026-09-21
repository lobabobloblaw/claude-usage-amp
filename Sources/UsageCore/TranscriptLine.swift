import Foundation

/// Turns one raw transcript line into a `UsageEvent`, after a byte-level prefilter.
///
/// The prefilter is the whole performance story: the multi-megabyte lines in a transcript are tool
/// results on `user` lines, and they are rejected by a `memmem` scan without ever reaching the JSON
/// parser (SPEC 4.1).
struct TranscriptLineParser {

    /// Interning pool, so 60 000 events do not each own a copy of the same session UUID / cwd /
    /// model string. Owned by the scan queue.
    private var pool: [String: String] = [:]

    private static let needleTokens = Array("\"input_tokens\"".utf8)
    private static let needleAssistant = Array("\"assistant\"".utf8)
    private static let needleUsage = Array("\"usage\"".utf8)

    /// Lines above this never reach `JSONSerialization`. A real assistant line is a few kilobytes;
    /// anything in the megabytes is a tool result that merely quotes the words we look for.
    static let maxParsedLineBytes = 4 << 20

    var parsedLines = 0
    var prefilterHits = 0

    /// Cheap rejection test. All three needles must be present.
    @inline(__always)
    static func passesPrefilter(_ line: UnsafeRawBufferPointer) -> Bool {
        guard line.count > 40 else { return false }
        guard ByteSearch.contains(line, needleTokens) else { return false }
        guard ByteSearch.contains(line, needleAssistant) else { return false }
        return ByteSearch.contains(line, needleUsage)
    }

    /// Parse one line that already passed the prefilter.
    /// `fallbackSession` is the session id derived from the file's path.
    mutating func event(from line: UnsafeRawBufferPointer, fallbackSession: String) -> UsageEvent? {
        guard line.count <= TranscriptLineParser.maxParsedLineBytes else { return nil }
        parsedLines += 1
        // `JSONSerialization` hands back autoreleased Foundation objects, and one assistant line
        // materialises its whole content array. Without a pool per line they pile up for the
        // length of the scan and the process footprint runs into the hundreds of megabytes.
        return autoreleasepool { () -> UsageEvent? in extract(line, fallbackSession: fallbackSession) }
    }

    private mutating func extract(_ line: UnsafeRawBufferPointer, fallbackSession: String) -> UsageEvent? {
        guard let root = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { return nil }
        guard (root["type"] as? String) == "assistant" else { return nil }
        guard let message = root["message"] as? [String: Any] else { return nil }
        guard let usage = message["usage"] as? [String: Any] else { return nil }
        guard let messageID = message["id"] as? String, !messageID.isEmpty else { return nil }

        let model = (message["model"] as? String) ?? ""
        guard !model.isEmpty, model != "<synthetic>" else { return nil }

        guard let ts = root["timestamp"] as? String, let epoch = ISO8601.epochSeconds(ts) else { return nil }

        var session = fallbackSession
        if session.isEmpty { session = (root["sessionId"] as? String) ?? (root["session_id"] as? String) ?? "" }
        let cwd = (root["cwd"] as? String) ?? ""

        let input = JSONNumber.int(usage["input_tokens"])
        let output = JSONNumber.int(usage["output_tokens"])
        var writeTotal = JSONNumber.int(usage["cache_creation_input_tokens"])
        let read = JSONNumber.int(usage["cache_read_input_tokens"])
        var write1h = 0
        if let split = usage["cache_creation"] as? [String: Any] {
            let a = JSONNumber.int(split["ephemeral_5m_input_tokens"])
            let b = JSONNumber.int(split["ephemeral_1h_input_tokens"])
            write1h = b
            if writeTotal <= 0 { writeTotal = a + b }
            if write1h > writeTotal { writeTotal = a + b }
        }

        // `usage.speed` is an enum ("standard" / "fast"); only the value "fast" means anything here.
        let fast = (usage["speed"] as? String) == "fast"

        // A line is data from another process: clamp rather than trust, so no later sum can trap.
        @inline(__always) func sane(_ v: Int) -> Int { min(max(0, v), Int(UsageEvent.maxTokenCount)) }

        return UsageEvent(id: messageID,
                          timestamp: epoch,
                          sessionID: intern(session),
                          cwd: intern(cwd),
                          model: intern(model),
                          input: sane(input),
                          output: sane(output),
                          cacheWriteTotal: sane(writeTotal),
                          cacheWrite1h: sane(write1h),
                          cacheRead: sane(read),
                          fast: fast)
    }

    @inline(__always)
    private mutating func intern(_ s: String) -> String {
        if let hit = pool[s] { return hit }
        if pool.count < 20_000 { pool[s] = s }
        return s
    }
}
