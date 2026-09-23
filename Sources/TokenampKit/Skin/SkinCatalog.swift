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

    public enum InstallError: Swift.Error, CustomStringConvertible {
        case containsSkinsFolder(String)

        public var description: String {
            switch self {
            case .containsSkinsFolder(let name):
                return "\(name) holds the skins folder itself - pick the skin's own folder"
            }
        }
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
    /// What is copied is bounded (amendment A8): a folder that is, or holds, the skins folder is
    /// refused outright (copying it into itself recursed dozens of levels deep on the main
    /// thread); of any other folder only the top-level files the loader reads are copied, each
    /// within its own limit; an archive over `SkinLoader.maximumArchiveBytes` is used where it is
    /// and not copied.
    ///
    /// - Returns: the loaded skin and the URL to remember for it: the installed copy, or the
    ///   original when it could not be copied.
    public static func install(_ url: URL,
                               into dir: URL = ResourceLocator.ensureUserSkinsDirectory()) throws -> (skin: Skin, url: URL) {
        if folder(url, contains: dir) { throw InstallError.containsSkinsFolder(url.lastPathComponent) }
        let skin = try SkinLoader.load(url: url)
        let fm = FileManager.default
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        if dest.standardizedFileURL == url.standardizedFileURL { return (skin, url) }
        let staging = dir.appendingPathComponent(".installing-\(UUID().uuidString)-\(url.lastPathComponent)")
        defer { try? fm.removeItem(at: staging) }
        do {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                try fm.createDirectory(at: staging, withIntermediateDirectories: false)
                for file in SkinLoader.folderMembers(url) where file.size <= file.member.byteLimit {
                    try fm.copyItem(at: file.url, to: staging.appendingPathComponent(file.url.lastPathComponent))
                }
            } else {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
                guard size <= SkinLoader.maximumArchiveBytes else { return (skin, url) }
                try fm.copyItem(at: url, to: staging)
            }
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

    /// True when `inner` is `outer` or lies anywhere below it. Compared by file identity, walking
    /// up from `inner`'s real path, so symlinks, `/private` aliases and letter case cannot hide it.
    static func folder(_ outer: URL, contains inner: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let target = try? outer.resolvingSymlinksInPath().resourceValues(forKeys: key).fileResourceIdentifier
        else { return false }
        var dir = inner.resolvingSymlinksInPath().standardizedFileURL
        for _ in 0..<dir.pathComponents.count {
            if let id = try? dir.resourceValues(forKeys: key).fileResourceIdentifier, id.isEqual(target) { return true }
            dir = dir.deletingLastPathComponent()
        }
        return false
    }

    /// True for the file types the app accepts by drag-and-drop or the Load Skin panel: a `.wsz`
    /// or `.zip` (SPEC 3), or a folder with a sheet of its own at the top (amendment A8), so that
    /// a folder of skins, the Skins folder or a home folder is turned away at the door.
    public static func isSkinURL(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        if isDir.boolValue { return SkinLoader.isSkinFolder(url) }
        return ["wsz", "zip"].contains(url.pathExtension.lowercased())
    }
}
