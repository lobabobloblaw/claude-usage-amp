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
    /// `usage.speed == "fast"`: the response was served in fast mode, which is priced at a premium
    /// (SPEC 4.2, amendment A5). Only the enum value is looked at, never any content.
    var fast: Bool = false

    @inline(__always) var cacheWrite5m: Int { max(0, cacheWriteTotal - cacheWrite1h) }

    @inline(__always) var counts: TokenCountsLite {
        TokenCountsLite(input: input, output: output, cacheWrite: cacheWriteTotal, cacheRead: cacheRead)
    }

    /// Merge another line of the same `message.id` **from the same file**.
    ///
    /// One API response is written once per content block with growing `output_tokens`, so the
    /// field-wise maximum reproduces "the values from the last line seen" while staying independent
    /// of line order. Identity fields keep the first line; the timestamp advances to the newest line
    /// of the response (when it finished). Across files the timestamp rule is the opposite: see
    /// `IndexEntry.combine`.
    @inline(__always)
    mutating func mergeWithinFile(_ other: UsageEvent) {
        timestamp = max(timestamp, other.timestamp)
        mergeCounts(other)
    }

    /// The order-independent part of every merge: token counts are the field-wise maximum and a
    /// response is fast if any sighting says so.
    @inline(__always)
    mutating func mergeCounts(_ other: UsageEvent) {
        input = max(input, other.input)
        output = max(output, other.output)
        cacheWriteTotal = max(cacheWriteTotal, other.cacheWriteTotal)
        cacheWrite1h = max(cacheWrite1h, other.cacheWrite1h)
        cacheRead = max(cacheRead, other.cacheRead)
        fast = fast || other.fast
    }
}

/// One entry of the global dedup index: the merged event plus the file that owns it.
///
/// Ownership rule (SPEC 4.1, amendment A5), the same on every path — cold scan, warm cache load,
/// tail, rebuild after eviction or truncation — and independent of the order files are read in:
/// each file contributes one sighting per id (its lines merged with `mergeWithinFile`, so its
/// timestamp is when the response finished *in that file*). The owner is the file whose sighting
/// is earliest, ties broken by the smaller path. The event takes the owner's timestamp and identity
/// (session, cwd, model) and the maximum token counts over all sightings. A resumed or forked
/// session that copies an old response with a new timestamp therefore neither takes the response
/// away from the session it was first seen in, nor drags it to "now".
struct IndexEntry {
    var event: UsageEvent
    /// Path of the owning file.
    var owner: String
    /// True once a second file has contributed a sighting. The incremental tail path can only
    /// maintain the rule by itself for single-file ids; a shared id is re-derived by a rebuild.
    var shared: Bool = false

    /// Fold in another file's sighting of the same id. Commutative and associative: the result does
    /// not depend on which file came first.
    @inline(__always)
    mutating func combine(sighting e: UsageEvent, path: String) {
        shared = true
        let incomingOwns = e.timestamp < event.timestamp || (e.timestamp == event.timestamp && path < owner)
        var merged = incomingOwns ? e : event
        merged.mergeCounts(incomingOwns ? event : e)
        if incomingOwns { owner = path }
        event = merged
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
