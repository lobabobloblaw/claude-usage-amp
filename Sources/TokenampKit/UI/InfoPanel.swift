import AppKit
import Foundation
import UsageModel

/// Clutterbar "I": where the numbers come from, how healthy each source is, and every path the
/// app is using - the first place to look when something is wrong (SPEC 2.1).
public enum InfoPanel {

    private static var panel: NSPanel?

    public static func show(app: TokenampController) {
        present(title: "Tokenamp - Data Sources", body: report(app: app))
    }

    public static func showAbout(app: TokenampController) {
        let body = """
        Tokenamp 1.0
        Your Claude account usage, as a Winamp 2.x player.

        It really whips the llama's tokens.

        Skin: \(app.skin.name)
        Scale: \(ScaleModel.label(app.scale)) (\(app.pixelsPerSkinPixel) device px per skin px)

        """ + report(app: app)
        present(title: "About Tokenamp", body: body)
    }

    public static func report(app: TokenampController) -> String {
        let snap = app.snapshot
        var lines: [String] = []

        lines.append("DATA SOURCES")
        lines.append("  Provider:     " + (app.isUsingDemoData ? "DemoUsageProvider (synthetic)" : providerLabel(app)))
        lines.append("  Live limits:  " + liveDescription(snap.liveStatus))
        lines.append("  Local scan:   " + localDescription(snap.localStatus))
        lines.append("  Plan:         " + (snap.planName.isEmpty ? "(unknown)" : snap.planName))
        lines.append("  Last event:   " + (snap.lastEventAt.map(stamp) ?? "(none)"))
        lines.append("  Snapshot at:  " + stamp(snap.generatedAt))
        let extra = app.isUsingDemoData ? [] : (app.providerDiagnostics?(app.provider) ?? [])
        if !extra.isEmpty {
            lines.append("")
            lines.append("LOCAL SCAN")
            lines.append(contentsOf: extra)
        }
        lines.append("")

        lines.append("LIMITS")
        if snap.limits.isEmpty {
            lines.append("  (none reported)")
        } else {
            for l in snap.limits {
                let resets = l.resetsAt.map(stamp) ?? "unknown"
                lines.append(String(format: "  %-20@ %5.1f%%  resets %@%@", l.title as NSString, l.percent,
                                    resets, l.isActive ? "  (active)" : ""))
            }
        }
        lines.append("")

        lines.append("SKIN")
        lines.append("  Name:         " + app.skin.name)
        lines.append("  Source:       " + (app.skin.sourceURL?.path ?? "built-in fallback"))
        if let err = app.skinLoadError { lines.append("  Load error:   " + err) }
        if app.skin.warnings.isEmpty {
            lines.append("  Warnings:     none")
        } else {
            lines.append("  Warnings:")
            for w in app.skin.warnings { lines.append("    - " + w) }
        }
        lines.append("  Sheets:")
        for s in app.skin.describeSheets() { lines.append("    " + s) }
        lines.append("")

        lines.append("PATHS")
        lines.append("  Bundled skins:   " + (ResourceLocator.bundledSkinsDirectory?.path ?? "(not found)"))
        lines.append("  User skins:      " + ResourceLocator.userSkinsDirectory.path)
        lines.append("  App support:     " + ResourceLocator.applicationSupportDirectory.path)
        lines.append("  Executable:      " + (Bundle.main.executablePath ?? "(unknown)"))
        lines.append("  Bundle id:       " + (Bundle.main.bundleIdentifier ?? "(none - running unbundled)"))
        return lines.joined(separator: "\n")
    }

    private static func providerLabel(_ app: TokenampController) -> String {
        app.liveProviderAvailable ? "LiveUsageProvider" : "DemoUsageProvider (live layer not wired in yet)"
    }

    private static func liveDescription(_ s: LiveStatus) -> String {
        switch s {
        case .disabled: return "disabled by the user"
        case .neverFetched: return "never fetched"
        case .ok(let at): return "ok, last fetch " + stamp(at)
        case .authExpired: return "auth expired - open Claude Code to refresh"
        case .rateLimited(let until): return "rate limited until " + stamp(until)
        case .error(let e): return "error: " + e
        }
    }

    private static func localDescription(_ s: LocalStatus) -> String {
        s.isScanning ? "scanning \(s.filesDone)/\(s.filesTotal)" : "idle, \(s.filesTotal) files"
    }

    private static func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    // MARK: - Presentation

    private static func present(title: String, body: String) {
        if let panel { panel.close() }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow],
                        backing: .buffered, defer: false)
        p.title = title
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        text.string = body
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.autoresizingMask = [.width]
        scroll.documentView = text
        p.contentView = scroll
        p.center()
        p.makeKeyAndOrderFront(nil)
        panel = p
    }
}
