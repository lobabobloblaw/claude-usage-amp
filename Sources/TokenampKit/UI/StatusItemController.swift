import AppKit
import Foundation
import UsageModel

/// The optional menu-bar readout: `42%·2h47m` for the hero limit (SPEC 2.6).
public final class StatusItemController: NSObject {

    private let item: NSStatusItem
    unowned let app: TokenampController

    init(app: TokenampController) {
        self.app = app
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        item.button?.title = "Tokenamp"
        item.menu = nil
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func update(snapshot: UsageSnapshot, now: Date) {
        let hero = HeroTrack.hero(in: snapshot, index: app.heroIndex) ?? snapshot.limits.first
        guard let hero else {
            item.button?.title = "Tokenamp"
            return
        }
        let pct = Int(min(999, max(0, hero.percent.rounded())))
        let left = hero.resetsAt.map { TimeFormatting.compactDuration($0.timeIntervalSince(now)).lowercased() } ?? "--"
        item.button?.title = "\(pct)%\u{00B7}\(left)"
        item.button?.toolTip = hero.title
    }

    @objc private func clicked() {
        // Pop the menu up directly; assigning `item.menu` and re-clicking the button would
        // re-enter this action.
        guard let button = item.button else { return }
        OptionsMenu.build(app: app).popUp(positioning: nil,
                                          at: NSPoint(x: 0, y: button.bounds.height + 4),
                                          in: button)
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }
}
