import Foundation
import UsageModel

/// Command-line arguments for the Tokenamp executable (SPEC 3.1).
public struct Arguments {
    public var snapshotDirectory: String?
    public var selftest = false
    public var skinPath: String?
    public var scale: Int?
    public var demo = false
    public var at: Date?
    public var state: String?
    public var help = false
    public var unknown: [String] = []

    public static let usage = """
    Tokenamp - your Claude usage, as a Winamp 2.x player.

      Tokenamp                                  run the app
      Tokenamp --demo                           run with deterministic synthetic data
      Tokenamp --snapshot <dir> [options]       render the windows to PNGs and exit
      Tokenamp --selftest                       run the built-in assertion suite and exit

    Options:
      --skin <path>        a .wsz / .zip / folder, or the name of a bundled skin
      --scale <N>          device pixels per skin pixel (PNG pixels per skin pixel for
                           --snapshot); whole number >= 1
      --demo               use DemoUsageProvider instead of live data
      --at <unix-seconds>  freeze the demo clock (default DemoUsageProvider.referenceDate)
      --state <name>       snapshot variant: normal (default) or pressed
    """

    public init(_ argv: [String]) {
        var i = 0
        func next() -> String? {
            guard i + 1 < argv.count else { return nil }
            i += 1
            return argv[i]
        }
        while i < argv.count {
            let arg = argv[i]
            switch arg {
            case "--snapshot": snapshotDirectory = next()
            case "--selftest": selftest = true
            case "--skin": skinPath = next()
            case "--scale": scale = next().flatMap { Int($0) }
            case "--demo": demo = true
            case "--at": at = next().flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
            case "--state": state = next()
            case "--help", "-h": help = true
            default:
                // Anything AppKit/launchd hands us (-NSDocumentRevisions...) is ignored.
                if arg.hasPrefix("--") { unknown.append(arg) }
            }
            i += 1
        }
    }

    /// `--scale` is ppsp - whole device/PNG pixels per skin pixel (SPEC 2.8/3.1). Capped so a
    /// typo cannot ask for a multi-gigabyte bitmap.
    public static let maximumScale = 16
    public var resolvedScale: Int { min(Arguments.maximumScale, max(1, scale ?? 2)) }

    /// The clock a demo run should use.
    public var demoClock: Date { at ?? DemoUsageProvider.referenceDate }

    /// How a `--skin` that loaded is remembered as the stored skin (SPEC 2.6). A path is stored
    /// absolute and standardized: a relative one (`skins/dist/X.wsz`) resolves against the working
    /// directory, and a later launch from Finder, whose working directory is `/`, would not find it
    /// and would fall back to Base without a word. The name of a bundled or installed skin stays a
    /// name. What counts as a path is what `SkinCatalog.url(for:)` loads as one: something that
    /// exists at the tilde-expanded spec.
    public static func rememberedSkinSpec(_ spec: String, currentDirectory: String,
                                          fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> String {
        let expanded = (spec as NSString).expandingTildeInPath
        guard fileExists(expanded) else { return spec }
        let base = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded)
                                          : URL(fileURLWithPath: expanded, relativeTo: base)
        // Lexically: `..` and `.` go, symbolic links stay as the user named them.
        return url.absoluteURL.standardized.path
    }
}
