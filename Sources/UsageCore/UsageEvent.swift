import Foundation
import UsageModel

/// One deduplicated API response, reduced to the fields the app is allowed to keep.
///
/// Nothing from `message.content` is ever read, stored or logged — only the identifiers and the
/// numbers below (SPEC 4.1, privacy rule).
struct UsageEvent {
    /// Largest token count any single field of any single event may carry. Nothing real comes
    /// within nine orders of magnitude of this; the cap exists because the counts are summed with
    /// Swift's trapping `+`, so one absurd number out of a malformed line or a corrupt cache would
    /// otherwise be an overflow crash in the aggregator rather than a wrong number.
    static let maxTokenCount: Double = 1_000_000_000_000

    /// `message.id`, the global dedup key.
    var id: String
    /// Epoch seconds, from the transcript `timestamp`.
    var timestamp: Double
    /// Parent session UUID (subagent transcripts are attributed to their parent).
    var sessionID: String
    /// `cwd` of the session, used only to build a short project label.
    var cwd: String
    /// Raw model id, e.g. `claude-opus-5`.
    var model: String
    var input: Int
    var output: Int
    /// `cache_creation_input_tokens` (5 m + 1 h combined).
    var cacheWriteTotal: Int
    /// `cache_creation.ephemeral_1h_input_tokens`; 0 when the split is absent, in which case the
    /// whole write is priced at the 5 m rate.
    var cacheWrite1h: Int
    var cacheRead: Int

    @inline(__always) var cacheWrite5m: Int { max(0, cacheWriteTotal - cacheWrite1h) }

    @inline(__always) var counts: TokenCountsLite {
        TokenCountsLite(input: input, output: output, cacheWrite: cacheWriteTotal, cacheRead: cacheRead)
    }

    /// Merge another sighting of the same `message.id`.
    ///
    /// One API response is written once per content block with growing `output_tokens`, so the
    /// field-wise maximum reproduces "the values from the last line seen" while staying independent
    /// of the order files happen to be scanned in. Identity fields keep the first sighting; the
    /// timestamp advances to the newest line of the response (when it finished).
    @inline(__always)
    mutating func merge(_ other: UsageEvent) {
        timestamp = max(timestamp, other.timestamp)
        input = max(input, other.input)
        output = max(output, other.output)
        cacheWriteTotal = max(cacheWriteTotal, other.cacheWriteTotal)
        cacheWrite1h = max(cacheWrite1h, other.cacheWrite1h)
        cacheRead = max(cacheRead, other.cacheRead)
    }
}

/// Small mirror of `TokenCounts` so UsageCore's hot loops do not go through the public struct.
struct TokenCountsLite {
    var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    @inline(__always) static func += (a: inout TokenCountsLite, b: TokenCountsLite) {
        a.input += b.input; a.output += b.output; a.cacheWrite += b.cacheWrite; a.cacheRead += b.cacheRead
    }
    var asPublic: TokenCounts { TokenCounts(input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead) }
}
