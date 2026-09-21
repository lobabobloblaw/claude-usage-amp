import AppKit
import Foundation
import UserNotifications
import UsageModel

/// What the Repeat toggle has already announced: one entry per limit, limit window and threshold
/// (SPEC 2.1: "once per limit per window"). A pure value, so `--selftest` drives it directly.
///
/// A window is named by its reset time **rounded to the minute**. The usage endpoint reports reset
/// times to the microsecond and the fraction can differ from one poll to the next; keyed on the
/// raw value, every poll looked like a new window and re-announced. Two minutes that differ by one
/// are also taken as the same window, so a reset time that straddles a rounding boundary
/// (hh:mm:29.9 on one poll, hh:mm:30.1 on the next) cannot slip through either. Real windows are
/// hours apart.
public struct AlertLedger: Equatable {

    public struct Entry: Hashable {
        public var limit: String
        /// `resetsAt` in whole minutes since 1970, nil when the limit reports no reset time.
        public var window: Int?
        public var threshold: Int
    }

    public private(set) var entries: Set<Entry> = []

    public init() {}

    public static func window(of resetsAt: Date?) -> Int? {
        resetsAt.map { Int(($0.timeIntervalSince1970 / 60).rounded()) }
    }

    private static func sameWindow(_ a: Int?, _ b: Int?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x - y) <= 1
        default: return false
        }
    }

    public func contains(limit: String, window: Int?, threshold: Int) -> Bool {
        entries.contains { $0.limit == limit && $0.threshold == threshold && AlertLedger.sameWindow($0.window, window) }
    }

    /// Record every threshold `limit` has reached in its current window, and return the highest one
    /// that was not recorded before - the one to announce - or nil.
    public mutating func record(_ limit: LimitGauge) -> Double? {
        let w = AlertLedger.window(of: limit.resetsAt)
        var fresh: Double?
        for t in ThresholdNotifier.thresholds where limit.percent >= t {
            let threshold = Int(t)
            guard !contains(limit: limit.id, window: w, threshold: threshold) else { continue }
            entries.insert(Entry(limit: limit.id, window: w, threshold: threshold))
            fresh = t
        }
        return fresh
    }

    /// Forget what no longer matters, so the ledger cannot grow without bound:
    /// - a window whose reset time has passed, unless a limit still reports that very window (a
    ///   stale reading would otherwise be announced again the moment its entry was dropped);
    /// - for a limit that reports no reset time, a threshold it has fallen back below, which is the
    ///   only sign such a limit gives that its window rolled over.
    public mutating func prune(current limits: [LimitGauge], now: Date) {
        let nowMinute = Int((now.timeIntervalSince1970 / 60).rounded(.down))
        entries = entries.filter { e in
            let reported = limits.first { $0.id == e.limit && AlertLedger.sameWindow(AlertLedger.window(of: $0.resetsAt), e.window) }
            guard let window = e.window else {
                // No reset time: keep it while the limit is still at or past that threshold, and
                // while the limit is not being reported at all (an outage is not a rollover).
                guard let reported else { return !limits.contains { $0.id == e.limit } }
                return reported.percent >= Double(e.threshold)
            }
            return window >= nowMinute - 1 || reported != nil
        }
    }

    // MARK: - Persistence

    /// `threshold|window|limit`, with the limit id last so it may contain anything; `-` for no window.
    public var encoded: [String] {
        entries.map { "\($0.threshold)|\($0.window.map(String.init) ?? "-")|\($0.limit)" }.sorted()
    }

    public init(encoded: [String]) {
        for line in encoded {
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let threshold = Int(parts[0]), !parts[2].isEmpty else { continue }
            let window: Int?
            if parts[1] == "-" { window = nil } else if let w = Int(parts[1]) { window = w } else { continue }
            entries.insert(Entry(limit: String(parts[2]), window: window, threshold: threshold))
        }
    }
}

/// The Repeat toggle: a user notification when any limit crosses 75 / 90 / 100 %, once per limit
/// per window (SPEC 2.1).
///
/// What has been announced is persisted (`AlertLedger`), so a relaunch does not announce again the
/// limits that were already past a threshold. With nothing stored yet - the first run of a build
/// that keeps a ledger, or Repeat just switched on - the first snapshot that carries limits is
/// recorded silently instead. A snapshot with no limits at all (the live source has not answered
/// yet, or its token expired) says nothing about the account and is ignored: it must not wipe the
/// ledger, or the recovery would announce everything again.
///
/// `UNUserNotificationCenter.current()` traps when the process has no bundle identifier, which is
/// exactly the case when Tokenamp is run straight from `swift build` output. Every call is
/// therefore gated on `Bundle.main.bundleIdentifier != nil`; unbundled runs simply beep.
public final class ThresholdNotifier {

    public static let thresholds: [Double] = [75, 90, 100]

    private var ledger: AlertLedger
    /// True until the ledger reflects the account: nothing was stored, or Repeat was just enabled
    /// while no limits were known. The first snapshot with limits is then recorded, not announced.
    private var needsPrime: Bool
    private let prefs: Preferences?
    private let deliver: (LimitGauge, Double) -> Void
    private var authorizationRequested = false

    /// - Parameters:
    ///   - prefs: where the ledger is kept between launches; nil keeps it in memory only.
    ///   - deliver: how an announcement is made; the default posts a user notification (or beeps
    ///     when unbundled). The self-test passes a recorder.
    public init(prefs: Preferences? = nil, deliver: ((LimitGauge, Double) -> Void)? = nil) {
        self.prefs = prefs
        self.deliver = deliver ?? ThresholdNotifier.post
        if let stored = prefs?.announcedAlerts {
            ledger = AlertLedger(encoded: stored)
            needsPrime = false
        } else {
            ledger = AlertLedger()
            needsPrime = true
        }
    }

    public static var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// What is on record, as persisted (for the self-test).
    public var announced: [String] { ledger.encoded }

    public func requestAuthorizationIfPossible() {
        guard ThresholdNotifier.notificationsAvailable, !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Record the current levels without firing, so enabling the toggle does not immediately
    /// announce limits that were already high. With no limits known yet, the first snapshot that
    /// has them is recorded instead.
    public func prime(snapshot: UsageSnapshot, now: Date = Date()) {
        guard !snapshot.limits.isEmpty else {
            needsPrime = true
            return
        }
        ledger.prune(current: snapshot.limits, now: now)
        for limit in snapshot.limits { _ = ledger.record(limit) }
        needsPrime = false
        save()
    }

    /// Record, rather than announce, the next snapshot that carries limits.
    public func primeOnNextSnapshot() { needsPrime = true }

    public func check(snapshot: UsageSnapshot, now: Date = Date()) {
        guard !snapshot.limits.isEmpty else { return }
        if needsPrime {
            prime(snapshot: snapshot, now: now)
            return
        }
        let before = ledger
        ledger.prune(current: snapshot.limits, now: now)
        for limit in snapshot.limits {
            if let crossed = ledger.record(limit) { deliver(limit, crossed) }
        }
        if ledger != before { save() }
    }

    private func save() {
        prefs?.announcedAlerts = ledger.encoded
    }

    private static func post(limit: LimitGauge, threshold: Double) {
        let title = "Tokenamp"
        let body = "\(limit.title) is at \(Int(limit.percent.rounded()))% (crossed \(Int(threshold))%)."
        guard ThresholdNotifier.notificationsAvailable else {
            // Unbundled: no notification centre. Make some noise instead of crashing.
            NSSound.beep()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
