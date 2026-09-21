import Foundation
import UsageModel

/// "Each plan limit is a track" (SPEC 2). The hero track is the limit that drives the big digits,
/// the seek bar and the head of the marquee; the transport's prev/next buttons choose it.
public enum HeroTrack {

    /// Clamp/wrap a stored hero index onto the snapshot's current tracklist.
    public static func resolveIndex(_ requested: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((requested % count) + count) % count
    }

    /// The hero limit, or nil when the live source has given us no limits at all.
    public static func hero(in snapshot: UsageSnapshot, index: Int) -> LimitGauge? {
        guard !snapshot.limits.isEmpty else { return nil }
        return snapshot.limits[resolveIndex(index, count: snapshot.limits.count)]
    }

    /// Track number as shown in the marquee, 1-based.
    public static func trackNumber(index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return resolveIndex(index, count: count) + 1
    }

    public static func next(_ index: Int, count: Int) -> Int { resolveIndex(index + 1, count: count) }
    public static func previous(_ index: Int, count: Int) -> Int { resolveIndex(index - 1, count: count) }

    /// Session limit utilisation for the volume gauge; 0 when unknown (SPEC 2.1).
    public static func sessionPercent(_ snapshot: UsageSnapshot) -> Double? {
        snapshot.limit(.session)?.percent
    }

    /// Weekly-all utilisation for the balance gauge.
    public static func weeklyPercent(_ snapshot: UsageSnapshot) -> Double? {
        snapshot.limit(.weeklyAll)?.percent
    }

    /// The model-scoped weekly limit if one exists, else weekly-all (EQ preamp, SPEC 2.3).
    public static func preampPercent(_ snapshot: UsageSnapshot) -> Double? {
        snapshot.limit(.weeklyScoped)?.percent ?? snapshot.limit(.weeklyAll)?.percent
    }
}
