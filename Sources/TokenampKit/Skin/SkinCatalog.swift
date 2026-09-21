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

    /// Load a dropped `.wsz`/`.zip`/folder and copy it into the user skins folder so it survives
    /// relaunches (SPEC 2.6).
    ///
    /// The skin is loaded **before** anything is copied, so one that does not load is never
    /// installed (the error is thrown and the folder is untouched). The copy goes to a hidden
    /// staging name first and replaces a same-named skin only once it is complete; whatever goes
    /// wrong on the way, the staging copy is removed and the original URL is returned, which still
    /// loads.
    ///
    /// - Returns: the loaded skin and the URL to remember for it: the installed copy, or the
    ///   original when it could not be copied.
    public static func install(_ url: URL,
                               into dir: URL = ResourceLocator.ensureUserSkinsDirectory()) throws -> (skin: Skin, url: URL) {
        let skin = try SkinLoader.load(url: url)
        let fm = FileManager.default
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        if dest.standardizedFileURL == url.standardizedFileURL { return (skin, url) }
        let staging = dir.appendingPathComponent(".installing-\(UUID().uuidString)-\(url.lastPathComponent)")
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.copyItem(at: url, to: staging)
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: dest)
            }
            return (skin, dest)
        } catch {
            return (skin, url)
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
