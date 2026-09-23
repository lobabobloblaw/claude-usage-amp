import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads a `.wsz` / `.zip` / plain directory into a `Skin`.
///
/// Lookup rules (SPEC 3, amendment A8):
///  * case-insensitive file names,
///  * any directory prefix inside the archive is ignored (skins are often zipped with a folder),
///    whether it is written with `/` or with Windows' `\`; a folder skin is its own top-level files
///    only, and its subfolders are never searched,
///  * images are `.bmp` or `.png` (a `.png` beats a `.bmp` when both exist), and the bytes must
///    really be a BMP or a PNG, whatever the name says,
///  * an archive or folder without a single sheet is not a skin,
///  * a sheet that is missing, undersized or undecodable never aborts the load; it becomes a
///    warning and falls back to the Base skin at draw time;
///  * so does one whose header claims a size far beyond anything a skin needs (`pixelLimit`): the
///    header is read before a single pixel is decoded;
///  * and so does any file larger than its kind can need (`byteLimit`), refused before it is read
///    or inflated.
public enum SkinLoader {

    public enum Error: Swift.Error, CustomStringConvertible {
        case unreadable(String)
        case empty(String)

        public var description: String {
            switch self {
            case .unreadable(let s): return s
            case .empty(let s): return "no skin bitmaps (main.bmp, ...) found in \(s)"
            }
        }
    }

    /// One candidate file from the archive/folder, keyed by its lower-cased stem. `load` enforces
    /// the file's byte limit before anything is read.
    private struct Candidate {
        var ext: String
        var load: () throws -> Data
    }

    /// Extensions a skin image may have (SPEC 3). Anything else (cursors, readmes, JPEG or TIFF art,
    /// stray junk) is ignored, so no other ImageIO codec is ever handed a skin's bytes.
    ///
    /// Images and text live in **separate** maps on purpose: `pledit.bmp` and `pledit.txt` share a
    /// stem, as do `plfont.bmp` and `plfont.txt`, and one map keyed by stem alone loses whichever
    /// of the pair the enumerator happened to reach second.
    static let imageExtensions: Set<String> = ["bmp", "png"]

    /// What ImageIO must find the bytes to be, checked before its codec parses them.
    static let imageTypes: Set<String> = [UTType.bmp.identifier, UTType.png.identifier]

    /// The text files a skin can carry. Any other `.txt` (a readme) is never read.
    static let textStems: Set<String> = ["viscolor", "pledit", "region", "plfont"]

    /// The pixel limit of every image the loader reads, by stem: the sheets, and `plfont`.
    static let imagePixelLimits: [String: SkinPair] = {
        var out = ["plfont": plfontPixelLimit]
        for spec in SkinSpec.sheets.values { out[spec.stem] = pixelLimit(for: spec) }
        return out
    }()

    /// A file name the loader reads, lower-cased and split, with the most bytes such a file may
    /// have. There is none for any other name, so nothing else is ever read or inflated.
    struct Member {
        let stem: String
        let ext: String
        let isImage: Bool
        let byteLimit: Int

        init?(fileName: String) {
            let lower = fileName.lowercased()
            guard !lower.hasPrefix("."), let dot = lower.lastIndex(of: ".") else { return nil }
            stem = String(lower[lower.startIndex..<dot])
            ext = String(lower[lower.index(after: dot)...])
            if SkinLoader.imageExtensions.contains(ext), let pixels = SkinLoader.imagePixelLimits[stem] {
                isImage = true
                byteLimit = SkinLoader.byteLimit(forPixels: pixels)
            } else if ext == "txt", SkinLoader.textStems.contains(stem) {
                isImage = false
                byteLimit = SkinLoader.maximumTextBytes
            } else {
                return nil
            }
        }
    }

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
            for file in folderMembers(url) {
                offer(file.member, images: &images, texts: &texts) {
                    try readFile(file.url, size: file.size, limit: file.member.byteLimit)
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
                // Either separator: PowerShell 5's Compress-Archive writes `Skin\main.bmp`.
                let base = entry.name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? entry.name
                if base.hasPrefix(".") { continue }          // __MACOSX/._foo and friends
                if entry.name.contains("__MACOSX") { continue }
                guard let member = Member(fileName: base) else { continue }
                offer(member, images: &images, texts: &texts) { try archive.extract(entry, limit: member.byteLimit) }
            }
        }

        guard !images.isEmpty else { throw Error.empty(url.lastPathComponent) }
        return build(name: name, sourceURL: url, images: images, texts: texts, warnings: warnings)
    }

    /// Name a skin after its file/folder: "Base.wsz" -> "Base".
    public static func defaultName(for url: URL) -> String {
        let base = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if ext == "wsz" || ext == "zip" { return String(base.dropLast(ext.count + 1)) }
        return base
    }

    // MARK: - Folder skins

    /// A folder skin's files: its own top-level regular files that the loader reads, with their
    /// sizes on disk. Subfolders are not searched, so a folder that merely holds skins (or the
    /// Skins folder itself, or a home folder) is not mistaken for one enormous skin.
    static func folderMembers(_ dir: URL) -> [(url: URL, member: Member, size: Int)] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys),
                                                                  options: [.skipsHiddenFiles])) ?? []
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { item in
            guard let member = Member(fileName: item.lastPathComponent),
                  let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return (item, member, values.fileSize ?? 0)
        }
    }

    /// True when `dir` has at least one sheet (`main.bmp`, `EQMAIN.PNG`, ...) among its own files:
    /// the test for "this folder is a skin".
    public static func isSkinFolder(_ dir: URL) -> Bool {
        folderMembers(dir).contains { $0.member.isImage }
    }

    /// Read a file no larger than `limit`: refused on its size before it is opened, and never read
    /// past the limit in case it grew in between.
    private static func readFile(_ url: URL, size: Int, limit: Int) throws -> Data {
        let tooLarge = Error.unreadable("\(url.lastPathComponent) is \(size) bytes, more than the \(limit) such a file may be")
        guard size <= limit else { throw tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw tooLarge }
        return data
    }

    private static func offer(_ member: Member, images: inout [String: Candidate],
                              texts: inout [String: Candidate],
                              _ load: @escaping () throws -> Data) {
        if member.isImage {
            if let existing = images[member.stem] {
                // .png beats .bmp; otherwise first one wins.
                guard member.ext == "png", existing.ext != "png" else { return }
            }
            images[member.stem] = Candidate(ext: member.ext, load: load)
        } else {
            if texts[member.stem] != nil { return }
            texts[member.stem] = Candidate(ext: member.ext, load: load)
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
            let image: CGImage
            switch loadImage(candidate, limit: pixelLimit(for: spec)) {
            case .success(.image(let decoded)):
                image = decoded
            case .success(.undecodable):
                warnings.append("\(spec.file) could not be decoded - using Base")
                continue
            case .success(.tooLarge(let size)):
                warnings.append("\(spec.file) claims to be \(size.w)x\(size.h), far beyond the "
                                + "\(spec.width)x\(spec.height) sheet - using Base")
                continue
            case .success(.wrongFormat(let format)):
                warnings.append("\(spec.file) is really \(format), not BMP or PNG - using Base")
                continue
            case .failure(let error):
                warnings.append("\(spec.file): \(error)")
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
        }

        // A text file that cannot be read (too large, a broken member) is skipped with a warning,
        // exactly as if it were missing.
        func text(_ stem: String) -> Data? {
            guard let c = texts[stem] else { return nil }
            do {
                return try c.load()
            } catch {
                warnings.append("\(stem).txt: \(error) - ignored")
                return nil
            }
        }

        var vis = VisColors.fallback
        var visPresent = false
        if let d = text("viscolor") {
            vis = VisColors.parse(d)
            visPresent = true
        }
        var pl = PleditColors.fallback
        if let d = text("pledit") {
            pl = PleditColors.parse(d)
        }
        var regions = SkinRegions()
        if let d = text("region") {
            regions = SkinRegions.parse(d)
            for kind in regions.oversized {
                warnings.append("region.txt: the \(kind.rawValue) shape has more than \(SkinRegions.maximumPoints) "
                                + "points - that window stays rectangular")
            }
        }

        // plfont: the Sessions-list typeface (SPEC 3.2). Both files are optional; a sheet whose
        // grid does not divide evenly is rejected with a warning and the skin falls back to Base's.
        var plfont: CGImage?
        if let c = images["plfont"] {
            switch loadImage(c, limit: plfontPixelLimit) {
            case .success(.image(let image)):
                if image.width % PlaylistFont.columns == 0 && image.height % PlaylistFont.rows == 0
                    && image.width > 0 && image.height > 0 {
                    plfont = image
                } else {
                    warnings.append("plfont is \(image.width)x\(image.height), which is not a "
                                    + "\(PlaylistFont.columns)x\(PlaylistFont.rows) grid - using Base's")
                }
            case .success(.undecodable):
                warnings.append("plfont could not be decoded - using Base's")
            case .success(.tooLarge(let size)):
                warnings.append("plfont claims to be \(size.w)x\(size.h), far beyond a font sheet - using Base's")
            case .success(.wrongFormat(let format)):
                warnings.append("plfont is really \(format), not BMP or PNG - using Base's")
            case .failure(let error):
                warnings.append("plfont: \(error) - using Base's")
            }
        }
        var plfontMetrics: PlaylistFontMetrics?
        if let d = text("plfont") {
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

    // MARK: - Size limits (amendment A8)

    /// The most bytes a text member may have. viscolor, pledit and plfont.txt are a few hundred
    /// bytes in every real skin; region.txt is the big one, and 128 KiB holds a shape at its point
    /// cap (`SkinRegions.maximumPoints`) written out in full. Four 64 MiB files of newlines in a
    /// 65 KB archive used to take a minute and 5 GB to parse, on the main thread, on every launch.
    public static let maximumTextBytes = 128 << 10

    /// Room in an image file for everything that is not pixels: BMP headers and a 256-colour
    /// palette, PNG chunks, an embedded colour profile.
    public static let imageOverheadBytes = 64 << 10

    /// The most bytes an image of at most `pixels` can need: four bytes a pixel, which is a 32-bit
    /// BMP, the widest classic layout (24-bit and palette BMPs are smaller, a PNG is compressed),
    /// plus `imageOverheadBytes`. From the sheet's own pixel limit, so eqmain, the largest sheet,
    /// may be about 5.3 MiB and the smallest ones 1 MiB.
    public static func byteLimit(forPixels pixels: SkinPair) -> Int {
        pixels.w * pixels.h * 4 + imageOverheadBytes
    }

    /// The largest archive worth copying into the user skins folder: every file the loader could
    /// read, each at its limit, uncompressed (about 35 MB; real skins are well under 1 MB).
    public static let maximumArchiveBytes: Int =
        imagePixelLimits.values.reduce(0) { $0 + byteLimit(forPixels: $1) } + textStems.count * maximumTextBytes

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
        /// Some format other than BMP or PNG, named for the warning ("TIFF").
        case wrongFormat(String)
    }

    /// Read and decode one image. The file's bytes exist only inside this call and its autorelease
    /// pool; what comes out holds none of them.
    private static func loadImage(_ candidate: Candidate, limit: SkinPair) -> Result<Decoded, Swift.Error> {
        autoreleasepool {
            do {
                return .success(decodeImage(try candidate.load(), ext: candidate.ext, limit: limit))
            } catch {
                return .failure(error)
            }
        }
    }

    /// BMP/PNG -> CGImage, refusing any other format before its codec parses the bytes and anything
    /// larger than `limit` before it is decoded. The image is decoded here and now, not on first
    /// draw, and copied into a bitmap of its own (`ownedCopy`), so a skin that loads is one whose
    /// pixels are already in hand and which keeps nothing of the file alive.
    static func decodeImage(_ data: Data, ext: String, limit: SkinPair) -> Decoded {
        guard !data.isEmpty else { return .undecodable }
        // The name only suggests a codec; ImageIO still sniffs the bytes. Whatever it found must be
        // BMP or PNG before anything asks the source for a count, properties or pixels.
        let hint = (ext == "png" ? UTType.png : UTType.bmp).identifier
        guard let src = CGImageSourceCreateWithData(data as CFData,
                                                    [kCGImageSourceTypeIdentifierHint: hint] as CFDictionary),
              let type = CGImageSourceGetType(src) as String? else { return .undecodable }
        guard imageTypes.contains(type) else {
            return .wrongFormat(UTType(type)?.preferredFilenameExtension?.uppercased() ?? type)
        }
        guard CGImageSourceGetCount(src) > 0 else { return .undecodable }
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
        guard let owned = ownedCopy(of: image) else { return .undecodable }
        return .image(owned)
    }

    /// `image` drawn into a bitmap this process allocates at the image's own size. An ImageIO image
    /// can keep the whole buffer it was decoded from alive for as long as it lives: eight sheets
    /// cut from 64 MiB members held 595 MB for the skin's lifetime. The copy holds only its pixels.
    ///
    /// The same pixels, not colour-matched ones: an RGB image keeps its own colour space and a
    /// palette image its palette's, so drawing the copy later converts exactly as drawing the
    /// original did. Opaque stays opaque; anything with alpha becomes premultiplied, which is what
    /// compositing does with it anyway.
    static func ownedCopy(of image: CGImage) -> CGImage? {
        var space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        if let own = image.colorSpace {
            if own.model == .rgb, own.supportsOutput {
                space = own
            } else if own.model == .indexed, let palette = own.baseColorSpace, palette.model == .rgb, palette.supportsOutput {
                space = palette
            }
        }
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let info = (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .none
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}
