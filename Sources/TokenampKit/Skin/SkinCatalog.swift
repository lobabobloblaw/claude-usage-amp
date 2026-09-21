import Foundation

/// Resolving "what skin should we show?" from a preference string, a CLI argument or a dropped
/// file, and installing user skins into Application Support (SPEC 2.6, 3).
public enum SkinCatalog {

    public static let defaultSkinName = "Base"

    public struct Entry {
        public let name: String
        public let url: URL
        public let isBundled: Bool
    }

    public static func entries() -> [Entry] {
        var out = ResourceLocator.bundledSkins().map {
            Entry(name: SkinLoader.defaultName(for: $0), url: $0, isBundled: true)
        }
        out += ResourceLocator.userSkins().map {
            Entry(name: SkinLoader.defaultName(for: $0), url: $0, isBundled: false)
        }
        return out
    }

    /// Interpret a `--skin` argument or a stored preference: an explicit path wins, otherwise the
    /// name of a bundled or installed skin.
    public static func url(for spec: String) -> URL? {
        let expanded = (spec as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }
        return ResourceLocator.skin(named: spec)
    }

    /// Load `spec`, falling back to the bundled Base skin and finally to the built-in stand-in.
    /// Never throws: a bad skin is a warning, not a dead app.
    public static func load(_ spec: String?) -> (skin: Skin, error: String?) {
        if let spec, !spec.isEmpty {
            if let url = url(for: spec) {
                do {
                    return (try SkinLoader.load(url: url), nil)
                } catch {
                    return (fallback(), "could not load skin \(spec): \(error)")
                }
            }
            return (fallback(), "no skin named \(spec)")
        }
        return (fallback(), nil)
    }

    private static func fallback() -> Skin {
        if let url = ResourceLocator.bundledSkin(named: defaultSkinName),
           let s = try? SkinLoader.load(url: url, name: defaultSkinName) {
            return s
        }
        return Skin.base
    }

    /// Copy a dropped `.wsz`/`.zip`/folder into the user skins folder so it survives relaunches.
    /// Returns the installed URL (or the original when the copy failed).
    @discardableResult
    public static func install(_ url: URL) -> URL {
        let dir = ResourceLocator.ensureUserSkinsDirectory()
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        if dest.standardizedFileURL == url.standardizedFileURL { return url }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return url
        }
    }

    /// True for the file types the app accepts by drag-and-drop or the Load Skin panel.
    public static func isSkinURL(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        if isDir.boolValue { return true }
        return ["wsz", "zip"].contains(url.pathExtension.lowercased())
    }
}
