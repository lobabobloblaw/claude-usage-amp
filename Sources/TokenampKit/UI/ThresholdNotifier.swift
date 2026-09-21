import AppKit
import Foundation
import UserNotifications
import UsageModel

/// The Repeat toggle: a user notification when any limit crosses 75 / 90 / 100 %, once per limit
/// per window (SPEC 2.1).
///
/// `UNUserNotificationCenter.current()` traps when the process has no bundle identifier, which is
/// exactly the case when Tokenamp is run straight from `swift build` output. Every call is
/// therefore gated on `Bundle.main.bundleIdentifier != nil`; unbundled runs simply beep.
public final class ThresholdNotifier {

    public static let thresholds: [Double] = [75, 90, 100]

    /// limit id + window start -> highest threshold already announced.
    private var announced: [String: Double] = [:]
    private var authorizationRequested = false

    public init() {}

    public static var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    public func requestAuthorizationIfPossible() {
        guard ThresholdNotifier.notificationsAvailable, !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Record the current levels without firing, so enabling the toggle does not immediately
    /// announce limits that were already high.
    public func prime(snapshot: UsageSnapshot) {
        for limit in snapshot.limits {
            announced[key(limit)] = ThresholdNotifier.thresholds.last(where: { limit.percent >= $0 }) ?? 0
        }
    }

    public func check(snapshot: UsageSnapshot) {
        for limit in snapshot.limits {
            let k = key(limit)
            let already = announced[k] ?? 0
            guard let crossed = ThresholdNotifier.thresholds.last(where: { limit.percent >= $0 }),
                  crossed > already else { continue }
            announced[k] = crossed
            fire(limit: limit, threshold: crossed)
        }
        // Forget windows that have rolled over so memory cannot grow without bound.
        let live = Set(snapshot.limits.map(key))
        announced = announced.filter { live.contains($0.key) }
    }

    private func key(_ limit: LimitGauge) -> String {
        "\(limit.id)@\(limit.resetsAt?.timeIntervalSince1970 ?? 0)"
    }

    private func fire(limit: LimitGauge, threshold: Double) {
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
