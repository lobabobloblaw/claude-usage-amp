import Foundation

/// Finds the bundled skins folder and the user's skins folder (SPEC 3, last bullet).
///
/// Order: `Bundle.main.resourceURL/Skins` when running from the assembled `.app`; else
/// `$TOKENAMP_RESOURCES`; else walk up from the executable and from the working directory
/// looking for `skins/dist`.
public enum ResourceLocator {

    public static let appSupportFolderName = "Tokenamp"

    /// Directory holding the bundled `*.wsz`, if one can be found.
    public static var bundledSkinsDirectory: URL? {
        for c in bundledSkinCandidates where isDirectory(c) { return c }
        return nil
    }

    /// Every place we are willing to look, in priority order (exposed for the info panel).
    public static var bundledSkinCandidates: [URL] {
        var out: [URL] = []
        if let res = Bundle.main.resourceURL {
            out.append(res.appendingPathComponent("Skins", isDirectory: true))
        }
        if let env = ProcessInfo.processInfo.environment["TOKENAMP_RESOURCES"], !env.isEmpty {
            let base = URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
            out.append(base)
            out.append(base.appendingPathComponent("Skins", isDirectory: true))
        }
        var roots: [URL] = []
        roots.append(URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent())
        if let exe = Bundle.main.executableURL { roots.append(exe.deletingLastPathComponent()) }
        roots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        for root in roots {
            var dir = root.standardizedFileURL
            for _ in 0..<8 {
                out.append(dir.appendingPathComponent("skins/dist", isDirectory: true))
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        return out
    }

    public static var userSkinsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appSupportFolderName, isDirectory: true)
            .appendingPathComponent("Skins", isDirectory: true)
    }

    public static var applicationSupportDirectory: URL {
        userSkinsDirectory.deletingLastPathComponent()
    }

    @discardableResult
    public static func ensureUserSkinsDirectory() -> URL {
        let dir = userSkinsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Every `*.wsz` / `*.zip` that ships with the app.
    public static func bundledSkins() -> [URL] {
        guard let dir = bundledSkinsDirectory else { return [] }
        return skinFiles(in: dir)
    }

    /// Every skin the user has installed (archives and plain folders).
    public static func userSkins() -> [URL] {
        let dir = userSkinsDirectory
        guard isDirectory(dir) else { return [] }
        var out = skinFiles(in: dir)
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        for item in items where isDirectory(item) { out.append(item) }
        return out.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func bundledSkin(named name: String) -> URL? {
        bundledSkins().first { SkinLoader.defaultName(for: $0).caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Any skin (bundled first, then user) whose name matches.
    public static func skin(named name: String) -> URL? {
        if let b = bundledSkin(named: name) { return b }
        return userSkins().first { SkinLoader.defaultName(for: $0).caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func skinFiles(in dir: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return items.filter { ["wsz", "zip"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
