import Foundation

/// Every filesystem location the data layer touches, in one place.
///
/// `TOKENAMP_SUPPORT_DIR` and `CLAUDE_CONFIG_DIR` are honoured so that the self-test (and anyone
/// debugging) can point the whole layer at a scratch directory without going near real data.
public enum TokenampPaths {

    public static var homeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// `~/.claude`, or `$CLAUDE_CONFIG_DIR` when set.
    public static var claudeConfigDirectory: URL {
        if let s = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !s.isEmpty {
            return URL(fileURLWithPath: (s as NSString).expandingTildeInPath, isDirectory: true)
        }
        return homeDirectory.appendingPathComponent(".claude", isDirectory: true)
    }

    /// `~/.claude/projects` — the transcript tree.
    public static var transcriptsRoot: URL {
        claudeConfigDirectory.appendingPathComponent("projects", isDirectory: true)
    }

    /// `~/Library/Application Support/Tokenamp`, or `$TOKENAMP_SUPPORT_DIR`.
    public static var supportDirectory: URL {
        if let s = ProcessInfo.processInfo.environment["TOKENAMP_SUPPORT_DIR"], !s.isEmpty {
            return URL(fileURLWithPath: (s as NSString).expandingTildeInPath, isDirectory: true)
        }
        return homeDirectory.appendingPathComponent("Library/Application Support/Tokenamp", isDirectory: true)
    }

    public static var scanCacheURL: URL { supportDirectory.appendingPathComponent("scan-cache.json") }
    public static var pricingURL: URL { supportDirectory.appendingPathComponent("pricing.json") }

    /// Fallback credential store used only when the keychain item is absent.
    public static var credentialsFallbackURL: URL {
        claudeConfigDirectory.appendingPathComponent(".credentials.json")
    }

    /// Fully resolved path (`/var/...` -> `/private/var/...`). `URL.resolvingSymlinksInPath()` is
    /// no good here: it deliberately strips a leading `/private`, which is the opposite of what the
    /// directory enumerator and FSEvents report.
    public static func realPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard let resolved = realpath(path, &buffer) else { return path }
        return String(cString: resolved)
    }

    @discardableResult
    public static func ensureSupportDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    /// Write `data` to `url` without ever leaving a half-written file behind.
    ///
    /// `Data.write(options: .atomic)` already writes a temporary file beside the destination and
    /// `rename(2)`s it into place, which is the atomicity we need. Doing the dance by hand on top
    /// of it only adds a window in which the old file has been deleted and the new one has not
    /// arrived yet — a crash there loses the cache for no benefit.
    static func writeAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
