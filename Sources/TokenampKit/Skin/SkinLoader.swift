import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads a `.wsz` / `.zip` / plain directory into a `Skin`.
///
/// Lookup rules (SPEC 3):
///  * case-insensitive file names,
///  * any directory prefix inside the archive is ignored (skins are often zipped with a folder),
///  * `.png` beats `.bmp` when both exist,
///  * a sheet that is missing, undersized or undecodable never aborts the load; it becomes a
///    warning and falls back to the Base skin at draw time;
///  * so does one whose header claims a size far beyond anything a skin needs (`pixelLimit`): the
///    header is read before a single pixel is decoded.
public enum SkinLoader {

    public enum Error: Swift.Error, CustomStringConvertible {
        case unreadable(String)
        case empty(String)

        public var description: String {
            switch self {
            case .unreadable(let s): return s
            case .empty(let s): return "no skin files found in \(s)"
            }
        }
    }

    /// One candidate file from the archive/folder, keyed by its lower-cased stem.
    private struct Candidate {
        var ext: String
        var load: () throws -> Data
    }

    /// Extensions ImageIO is asked to decode. Everything else with a known role (`.txt`) is text;
    /// anything else (cursors, readmes with odd extensions, stray junk) is ignored.
    ///
    /// Images and text live in **separate** maps on purpose: `pledit.bmp` and `pledit.txt` share a
    /// stem, as do `plfont.bmp` and `plfont.txt`, and one map keyed by stem alone loses whichever
    /// of the pair the enumerator happened to reach second.
    private static let imageExtensions: Set<String> = ["bmp", "png", "gif", "jpg", "jpeg", "tif", "tiff"]
    private static let textExtensions: Set<String> = ["txt"]

    public static func load(url: URL, name explicitName: String? = nil) throws -> Skin {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw Error.unreadable("no such skin: \(url.path)")
        }
        let name = explicitName ?? defaultName(for: url)
        var warnings: [String] = []
        var images: [String: Candidate] = [:]
        var texts: [String: Candidate] = [:]

        if isDir.boolValue {
            let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                   options: [.skipsHiddenFiles])
            while let item = e?.nextObject() as? URL {
                guard (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                offer(item.lastPathComponent, images: &images, texts: &texts) {
                    // The same bound an archive member gets (`ZipArchive.maximumMemberBytes`),
                    // checked before the file is read into memory.
                    let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    guard size <= ZipArchive.maximumMemberBytes else {
                        throw Error.unreadable("\(item.lastPathComponent) is \(size) bytes, more than a skin file may be")
                    }
                    return try Data(contentsOf: item)
                }
            }
        } else {
            let archive: ZipArchive
            do {
                archive = try ZipArchive(url: url)
            } catch {
                throw Error.unreadable("\(url.lastPathComponent): \(error)")
            }
            if !archive.skipped.isEmpty {
                warnings.append("skipped \(archive.skipped.count) unreadable archive member(s): "
                                + archive.skipped.prefix(4).joined(separator: ", "))
            }
            for entry in archive.entries {
                let base = entry.name.split(separator: "/").last.map(String.init) ?? entry.name
                if base.hasPrefix(".") { continue }          // __MACOSX/._foo and friends
                if entry.name.contains("__MACOSX") { continue }
                offer(base, images: &images, texts: &texts) { try archive.extract(entry) }
            }
        }

        guard !images.isEmpty || !texts.isEmpty else { throw Error.empty(url.lastPathComponent) }
        return build(name: name, sourceURL: url, images: images, texts: texts, warnings: warnings)
    }

    /// Name a skin after its file/folder: "Base.wsz" -> "Base".
    public static func defaultName(for url: URL) -> String {
        let base = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if ext == "wsz" || ext == "zip" { return String(base.dropLast(ext.count + 1)) }
        return base
    }

    private static func offer(_ fileName: String, images: inout [String: Candidate],
                              texts: inout [String: Candidate],
                              _ load: @escaping () throws -> Data) {
        let lower = fileName.lowercased()
        guard let dot = lower.lastIndex(of: ".") else { return }
        let stem = String(lower[lower.startIndex..<dot])
        let ext = String(lower[lower.index(after: dot)...])
        guard !stem.isEmpty else { return }
        if imageExtensions.contains(ext) {
            if let existing = images[stem] {
                // .png beats .bmp; otherwise first one wins.
                guard ext == "png", existing.ext != "png" else { return }
            }
            images[stem] = Candidate(ext: ext, load: load)
        } else if textExtensions.contains(ext) {
            if texts[stem] != nil { return }
            texts[stem] = Candidate(ext: ext, load: load)
        }
    }

    private static func build(name: String, sourceURL: URL?, images: [String: Candidate],
                              texts: [String: Candidate], warnings initialWarnings: [String]) -> Skin {
        var warnings = initialWarnings
        var sheets: [SheetID: CGImage] = [:]

        for id in SkinSpec.sheetOrder {
            guard let spec = SkinSpec.sheets[id] else { continue }
            guard let candidate = images[spec.stem] else {
                if spec.required { warnings.append("missing \(spec.file) - using Base") }
                continue
            }
            do {
                let data = try candidate.load()
                let image: CGImage
                switch decodeImage(data, limit: pixelLimit(for: spec)) {
                case .image(let decoded):
                    image = decoded
                case .undecodable:
                    warnings.append("\(spec.file) could not be decoded - using Base")
                    continue
                case .tooLarge(let size):
                    warnings.append("\(spec.file) claims to be \(size.w)x\(size.h), far beyond the "
                                    + "\(spec.width)x\(spec.height) sheet - using Base")
                    continue
                }
                // `gen` is a Tokenamp extension that happens to share a filename with a sheet
                // from later classic Winamp versions (SPEC 3.3). Slicing a foreign gen.bmp at
                // Tokenamp's coordinates would produce garbage, so only an exact match is taken
                // and anything else quietly falls back to Base's frame.
                if id == .gen, image.width != spec.width || image.height != spec.height {
                    warnings.append("\(spec.file) is \(image.width)x\(image.height), not the "
                                    + "\(spec.width)x\(spec.height) Tokenamp frame - using Base's")
                    continue
                }
                if image.width < spec.width || image.height < spec.height {
                    warnings.append("\(spec.file) is \(image.width)x\(image.height), expected "
                                    + "\(spec.width)x\(spec.height) - sprites outside it are skipped")
                }
                sheets[id] = image
            } catch {
                warnings.append("\(spec.file): \(error)")
            }
        }

        var vis = VisColors.fallback
        var visPresent = false
        if let c = texts["viscolor"], let d = try? c.load() {
            vis = VisColors.parse(d)
            visPresent = true
        }
        var pl = PleditColors.fallback
        if let c = texts["pledit"], let d = try? c.load() {
            pl = PleditColors.parse(d)
        }
        var regions = SkinRegions()
        if let c = texts["region"], let d = try? c.load() {
            regions = SkinRegions.parse(d)
        }

        // plfont: the Sessions-list typeface (SPEC 3.2). Both files are optional; a sheet whose
        // grid does not divide evenly is rejected with a warning and the skin falls back to Base's.
        var plfont: CGImage?
        if let c = images["plfont"] {
            let decoded = (try? c.load()).map { decodeImage($0, limit: plfontPixelLimit) } ?? .undecodable
            switch decoded {
            case .image(let image):
                if image.width % PlaylistFont.columns == 0 && image.height % PlaylistFont.rows == 0
                    && image.width > 0 && image.height > 0 {
                    plfont = image
                } else {
                    warnings.append("plfont is \(image.width)x\(image.height), which is not a "
                                    + "\(PlaylistFont.columns)x\(PlaylistFont.rows) grid - using Base's")
                }
            case .undecodable:
                warnings.append("plfont could not be decoded - using Base's")
            case .tooLarge(let size):
                warnings.append("plfont claims to be \(size.w)x\(size.h), far beyond a font sheet - using Base's")
            }
        }
        var plfontMetrics: PlaylistFontMetrics?
        if let c = texts["plfont"], let d = try? c.load() {
            plfontMetrics = PlaylistFontMetrics.parse(d)
        }

        if sheets.isEmpty {
            warnings.append("no usable bitmaps - everything falls back to Base")
        }
        if !visPresent { warnings.append("no viscolor.txt - using the stock palette") }

        return Skin(name: name, sourceURL: sourceURL, sheets: sheets, visColors: vis,
                    pledit: pl, regions: regions, plfontSheet: plfont, plfontMetrics: plfontMetrics,
                    warnings: warnings)
    }

    // MARK: - Decoding, bounded

    /// The largest image accepted for a sheet: four times its spec size in each dimension, and never
    /// less than 512 px, which is room for any real skin - including one drawn at 4x.
    ///
    /// A few hundred bytes of header can claim any size: a 270-byte `.wsz` whose main.bmp says
    /// 30000x30000 took the app to 3.6 GB, a 1.7 KB PNG to 922 MB. The size is read from the header
    /// first (`CGImageSourceCopyPropertiesAtIndex` decodes nothing), and a sheet over the limit is
    /// treated as missing, so Base's stands in.
    public static func pixelLimit(for spec: SheetSpec) -> SkinPair {
        SkinPair(max(minimumPixelLimit, 4 * spec.width), max(minimumPixelLimit, 4 * spec.height))
    }

    public static let minimumPixelLimit = 512

    /// `plfont` has no fixed size (SPEC 3.2): four times the recommended 128x60 sheet, with the
    /// same 512 px floor - cells up to 32x85 skin pixels.
    public static let plfontPixelLimit = SkinPair(max(minimumPixelLimit, 4 * 128), max(minimumPixelLimit, 4 * 60))

    enum Decoded {
        case image(CGImage)
        case undecodable
        case tooLarge(SkinPair)
    }

    /// BMP/PNG (and anything else ImageIO knows) -> CGImage, refusing anything larger than `limit`
    /// before it is decoded. The image is decoded here and now, not on first draw, so a skin that
    /// loads is one whose pixels are already in hand.
    static func decodeImage(_ data: Data, limit: SkinPair) -> Decoded {
        guard !data.isEmpty,
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(src) > 0 else { return .undecodable }
        // An image whose header gives no size is not one we can bound, so it is not decoded.
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              w > 0, h > 0 else { return .undecodable }
        guard w <= limit.w, h <= limit.h else { return .tooLarge(SkinPair(w, h)) }
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary) else { return .undecodable }
        // Belt and braces: what came out must agree with what the header promised.
        guard image.width <= limit.w, image.height <= limit.h else { return .tooLarge(SkinPair(image.width, image.height)) }
        return .image(image)
    }
}
