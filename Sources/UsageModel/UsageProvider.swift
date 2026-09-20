import Foundation

/// A source of usage snapshots. Implementations own their own threads/timers.
///
/// Threading contract: `start`, `stop`, `refreshNow`, the setters and `snapshot` are called on the
/// main thread. `onChange` is always invoked on the main thread. Providers publish a fresh snapshot
/// at least once per second while running (time moves the buckets even when no new data arrives),
/// and immediately when new data lands.
public protocol UsageProvider: AnyObject {
    /// Latest snapshot. Cheap to read.
    var snapshot: UsageSnapshot { get }
    var onChange: ((UsageSnapshot) -> Void)? { get set }

    /// Paused = keep the last snapshot, do no polling/scanning work. (The Pause transport button.)
    var isPaused: Bool { get set }
    /// Whether the live plan-limit source (account API) may be used. When false only local transcripts are read.
    var isLiveEnabled: Bool { get set }
    /// Seconds between live polls while there is local activity. Providers clamp to 30...900.
    var livePollInterval: TimeInterval { get set }

    func start()
    func stop()
    /// Force an immediate live poll + local rescan of changed files. (The Play transport button.)
    func refreshNow()
}
