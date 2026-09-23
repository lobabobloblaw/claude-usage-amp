import Compression
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Regression checks for amendment A8: a skin is untrusted input from the internet. Size limits
/// per kind of file, checked before anything is read or inflated; region.txt's point cap; decoded
/// images that keep nothing of the file alive; BMP and PNG only, whatever the name says; folders
/// that are skins only by their own top-level sheets, and installs that cannot copy the skins
/// folder into itself; Windows `\` in archive names; and a skin double-clicked in Finder to launch
/// the app. Every hostile input is built here from bytes; nothing is checked in.
extension SelfTest {

    static func skinInputLimits(_ c: Checker, tmp: URL) {
        let dir = tmp.appendingPathComponent("skin-input", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        memberSizeCaps(c, tmp: dir)
        regionPointCap(c, tmp: dir)
        ownedBitmaps(c)
        formatSniffing(c, tmp: dir)
        folderRules(c, tmp: dir)
        backslashNames(c, tmp: dir)
        launchDocuments(c, tmp: dir)
    }

    private static let mainBMP = makeBMPData(width: 275, height: 116, colour: (40, 50, 60))

    // MARK: - 1. Size caps, before extraction and during inflate

    private static func memberSizeCaps(_ c: Checker, tmp: URL) {
        c.section("skin input: size caps per kind of file (A8)")

        // The limits themselves, derived from the pixel limits rather than picked.
        let eqmain = SkinLoader.pixelLimit(for: SkinSpec.sheets[.eqmain]!)
        c.equal("an image may be 4 bytes a pixel of its pixel limit, plus headers",
                SkinLoader.byteLimit(forPixels: eqmain), eqmain.w * eqmain.h * 4 + SkinLoader.imageOverheadBytes)
        let sheetLimits = SkinSpec.sheets.values.map { SkinLoader.byteLimit(forPixels: SkinLoader.pixelLimit(for: $0)) }
        c.check("no sheet may be more than 6 MiB", sheetLimits.allSatisfy { $0 <= 6 << 20 })
        c.check("every sheet may be a 4x-drawn 32-bit BMP",
                SkinSpec.sheets.values.allSatisfy { spec in
                    SkinLoader.byteLimit(forPixels: SkinLoader.pixelLimit(for: spec)) >= 54 + 16 * spec.width * spec.height * 4
                })
        c.equal("text files are capped at 128 KiB", SkinLoader.maximumTextBytes, 128 << 10)
        c.check("the archive install cap covers every member at its limit",
                SkinLoader.maximumArchiveBytes >= sheetLimits.reduce(0, +))

        // ZipArchive: a declared size over the caller's limit is refused before any inflating.
        let stream = Data(repeating: 0x0A, count: 1 << 20)
        let text = HostileZip.make([.init(names: ["region.txt"], payload: stream)])
        if let archive = try? ZipArchive(data: text), let entry = archive.entries.first {
            var refused = false
            do { _ = try archive.extract(entry, limit: SkinLoader.maximumTextBytes) } catch { refused = true }
            c.check("a 1 MiB text member is refused at the text cap", refused)
            c.equal("and still extracts under a limit that allows it",
                    (try? archive.extract(entry, limit: 1 << 20))?.count, 1 << 20)
        } else {
            c.check("the text-bomb archive parses", false)
        }

        // A stream that inflates to far more than it declares stops at the declared size.
        let liar = HostileZip.make([.init(names: ["viscolor.txt"], payload: stream, declaredSize: 100)])
        if let archive = try? ZipArchive(data: liar), let entry = archive.entries.first {
            let out = try? archive.extract(entry, limit: SkinLoader.maximumTextBytes)
            c.check("inflating stops at the declared size", (out?.count ?? 0) <= 100)
        } else {
            c.check("the lying archive parses", false)
        }

        // A stored member is copied as is, so its stored size is what has to fit.
        let stored = HostileZip.make([.init(names: ["pledit.txt"], payload: Data(repeating: 0x41, count: 4_096),
                                            deflate: false, declaredSize: 10)])
        if let archive = try? ZipArchive(data: stored), let entry = archive.entries.first {
            var refused = false
            do { _ = try archive.extract(entry, limit: 1_000) } catch { refused = true }
            c.check("a stored member larger than its limit is refused whatever it declares", refused)
        } else {
            c.check("the stored archive parses", false)
        }

        // The loader: text bombs (the four files, each 1 MiB of newlines) next to a good sheet.
        let newlines = tmp.appendingPathComponent("newlines.wsz")
        try? HostileZip.make([
            .init(names: ["main.bmp"], payload: mainBMP),
            .init(names: ["viscolor.txt", "pledit.txt", "region.txt", "plfont.txt"], payload: stream),
        ]).write(to: newlines)
        if let skin = try? SkinLoader.load(url: newlines) {
            c.check("text bombs: the good sheet still loads", skin.hasOwnSheet(.main))
            for file in ["viscolor.txt", "pledit.txt", "region.txt", "plfont.txt"] {
                c.check("text bombs: \(file) is refused with a warning",
                        skin.warnings.contains { $0.hasPrefix(file) && $0.contains("bytes") })
            }
            c.check("text bombs: the stock palette stands in", skin.visColors == VisColors.fallback)
            c.check("text bombs: no window shape", skin.regions[.normal] == nil)
        } else {
            c.check("the text-bomb skin loads", false)
        }

        // A text file of exactly the cap is read; one byte more is not.
        let atCap = tmp.appendingPathComponent("at-cap.wsz")
        var palette = Data("1,2,3\n".utf8)
        palette.append(Data(repeating: 0x3B, count: SkinLoader.maximumTextBytes - palette.count))   // ";;;;"
        var overCap = Data("4,5,6\n".utf8)
        overCap.append(Data(repeating: 0x3B, count: SkinLoader.maximumTextBytes + 1 - overCap.count))
        try? HostileZip.make([.init(names: ["main.bmp"], payload: mainBMP),
                              .init(names: ["viscolor.txt"], payload: palette),
                              .init(names: ["pledit.txt"], payload: overCap)]).write(to: atCap)
        if let skin = try? SkinLoader.load(url: atCap) {
            c.check("a text file of exactly the cap is read", skin.visColors.rgb[0] == (1, 2, 3))
            c.check("one byte over is not", skin.warnings.contains { $0.hasPrefix("pledit.txt") })
        } else {
            c.check("the at-cap skin loads", false)
        }

        // An overlapping image bomb: every sheet name points at one 8 MiB member of zeros behind a
        // real BMP header. Each is refused by its declared size, before a byte is inflated.
        var bombBody = mainBMP.prefix(54)
        bombBody.append(Data(count: (8 << 20) - 54))
        let bomb = tmp.appendingPathComponent("image-bomb.wsz")
        let sheetNames = SkinSpec.sheetOrder.compactMap { SkinSpec.sheets[$0]?.file } + ["plfont.bmp"]
        try? HostileZip.make([.init(names: sheetNames, payload: bombBody)]).write(to: bomb)
        if let skin = try? SkinLoader.load(url: bomb) {
            c.check("image bomb: every sheet is refused",
                    SheetID.allCases.allSatisfy { !skin.hasOwnSheet($0) } && !skin.hasOwnPlaylistFont)
            c.equal("image bomb: each one says why", skin.warnings.filter { $0.contains("8388608 bytes") }.count,
                    sheetNames.count)
        } else {
            c.check("the image-bomb skin loads with Base fallbacks", false)
        }

        // A folder skin: the same caps, from the file size, before the file is opened (sparse).
        let folder = tmp.appendingPathComponent("BigText", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? mainBMP.write(to: folder.appendingPathComponent("main.bmp"))
        sparseFile(folder.appendingPathComponent("region.txt"), size: SkinLoader.maximumTextBytes + 1)
        sparseFile(folder.appendingPathComponent("titlebar.bmp"),
                   size: SkinLoader.byteLimit(forPixels: SkinLoader.pixelLimit(for: SkinSpec.sheets[.titlebar]!)) + 1)
        if let skin = try? SkinLoader.load(url: folder) {
            c.check("folder: an oversized region.txt is not read", skin.warnings.contains { $0.hasPrefix("region.txt") })
            c.check("folder: nor an oversized sheet", !skin.hasOwnSheet(.titlebar)
                    && skin.warnings.contains { $0.hasPrefix("titlebar.bmp") && $0.contains("bytes") })
            c.check("folder: the rest loads", skin.hasOwnSheet(.main))
        } else {
            c.check("the oversized-folder skin loads", false)
        }
    }

    // MARK: - region.txt point cap

    private static func regionPointCap(_ c: Checker, tmp: URL) {
        c.section("skin input: region.txt point cap (A8)")
        func region(points: Int) -> Data {
            // One polygon of `points` points plus a normal equalizer shape.
            let coords = (0..<points).map { "\($0 % 275),\($0 % 116)" }.joined(separator: ",")
            return Data("[Normal]\nNumPoints=\(points)\nPointList=\(coords)\n[Equalizer]\nNumPoints=4\nPointList=0,0,275,0,275,116,0,116\n".utf8)
        }
        let max = SkinRegions.maximumPoints
        let atCap = SkinRegions.parse(region(points: max))
        c.equal("a shape at the cap is kept", atCap[.normal]?.polygons.first?.count, max)
        c.check("and not reported", atCap.oversized.isEmpty)
        let over = SkinRegions.parse(region(points: max + 1))
        c.check("one point more drops the whole shape", over[.normal] == nil)
        c.equal("and says which", over.oversized, [.normal])
        c.equal("other windows keep theirs", over[.equalizer]?.polygons.first?.count, 4)

        // Many small polygons count the same as one big one.
        let triangles = (max / 3) + 1
        let many = "[WindowShade]\nNumPoints=" + Array(repeating: "3", count: triangles).joined(separator: ",")
            + "\nPointList=" + Array(repeating: "0,0,2,0,2,2", count: triangles).joined(separator: ",") + "\n"
        c.equal("thousands of triangles over the cap are dropped too",
                SkinRegions.parse(Data(many.utf8)).oversized, [.windowShade])

        // Through the loader: a warning, and the window stays rectangular.
        let url = tmp.appendingPathComponent("region-cap.wsz")
        try? HostileZip.make([.init(names: ["main.bmp"], payload: mainBMP),
                              .init(names: ["region.txt"], payload: region(points: max + 1))]).write(to: url)
        if let skin = try? SkinLoader.load(url: url) {
            c.check("loader: the oversized shape is dropped", skin.regions[.normal] == nil && skin.regions[.equalizer] != nil)
            c.check("loader: with a warning", skin.warnings.contains { $0.hasPrefix("region.txt") && $0.contains("Normal") })
        } else {
            c.check("the region-cap skin loads", false)
        }
    }

    // MARK: - 2. Decoded images keep nothing of the file

    private static func ownedBitmaps(_ c: Checker) {
        c.section("skin input: decoded sheets own their pixels (A8)")
        let opts = [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        let limit = SkinPair(512, 512)

        // Control: an image straight from ImageIO keeps the bytes it was decoded from alive. If it
        // does not on this system, the check below cannot tell the difference and is skipped.
        weak var controlSource: NSData?
        var control: CGImage?
        autoreleasepool {
            let bytes = NSData(data: mainBMP)
            controlSource = bytes
            if let src = CGImageSourceCreateWithData(Data(referencing: bytes) as CFData, nil) {
                control = CGImageSourceCreateImageAtIndex(src, 0, opts)
            }
        }
        weak var loadedSource: NSData?
        var loaded: CGImage?
        autoreleasepool {
            let bytes = NSData(data: mainBMP)
            loadedSource = bytes
            if case .image(let image) = SkinLoader.decodeImage(Data(referencing: bytes), ext: "bmp", limit: limit) {
                loaded = image
            }
        }
        // Both images must outlive the checks, or ARC may release them early and prove nothing.
        withExtendedLifetime((control, loaded)) {
            c.check("a sheet decodes", loaded != nil)
            if control != nil, controlSource != nil {
                c.check("the decoded sheet holds no reference to the file's bytes", loaded != nil && loadedSource == nil)
            } else {
                c.skip("the decoded sheet holds no reference to the file's bytes", "ImageIO released its source by itself")
            }
        }

        // The copy is the same pixels, not colour-matched ones, in every layout a skin uses.
        let fixtures: [(String, String, Data?)] = [
            ("24-bit BMP", "bmp", noiseBMP(width: 40, height: 20, bitsPerPixel: 24)),
            ("32-bit BMP", "bmp", noiseBMP(width: 40, height: 20, bitsPerPixel: 32)),
            ("8-bit palette BMP", "bmp", noiseBMP(width: 40, height: 20, bitsPerPixel: 8)),
            ("PNG with alpha", "png", ImageMaker.make(width: 40, height: 20) { canvas in
                canvas.fill(CGRect(x: 0, y: 0, width: 40, height: 20), CGColor(srgbRed: 0.9, green: 0.2, blue: 0.1, alpha: 1))
                canvas.fill(CGRect(x: 5, y: 5, width: 20, height: 10), CGColor(srgbRed: 0.1, green: 0.8, blue: 0.3, alpha: 0.4))
            }.flatMap { ImageMaker.pngData($0) }),
        ]
        for (label, ext, data) in fixtures {
            guard let data, let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let original = CGImageSourceCreateImageAtIndex(src, 0, opts) else {
                c.check("\(label): fixture decodes", false)
                continue
            }
            guard case .image(let copy) = SkinLoader.decodeImage(data, ext: ext, limit: limit) else {
                c.check("\(label): loads", false)
                continue
            }
            c.check("\(label): the owned copy draws exactly like the ImageIO image",
                    rendered(copy) != nil && rendered(copy) == rendered(original))
        }
    }

    // MARK: - 3. BMP and PNG only

    private static func formatSniffing(_ c: Checker, tmp: URL) {
        c.section("skin input: BMP and PNG only, whatever the name says (A8)")
        guard let art = ImageMaker.make(width: 275, height: 116, { $0.fill(CGRect(x: 0, y: 0, width: 275, height: 116),
                                                                           CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) }),
              let tiff = encode(art, as: .tiff), let jpeg = encode(art, as: .jpeg), let gif = encode(art, as: .gif),
              let png = ImageMaker.pngData(art) else {
            c.check("format fixtures encode", false)
            return
        }
        let limit = SkinLoader.pixelLimit(for: SkinSpec.sheets[.main]!)
        func rejected(_ d: SkinLoader.Decoded) -> String? {
            if case .wrongFormat(let f) = d { return f }
            return nil
        }
        c.equal("TIFF bytes named .bmp are refused", rejected(SkinLoader.decodeImage(tiff, ext: "bmp", limit: limit)), "TIFF")
        c.equal("JPEG bytes named .bmp are refused", rejected(SkinLoader.decodeImage(jpeg, ext: "bmp", limit: limit)), "JPEG")
        c.equal("GIF bytes named .png are refused", rejected(SkinLoader.decodeImage(gif, ext: "png", limit: limit)), "GIF")
        c.check("a PNG named .bmp is still a format the spec allows",
                rejected(SkinLoader.decodeImage(png, ext: "bmp", limit: limit)) == nil)

        // Through the loader, as the review's format_sniff.wsz did it.
        let sniff = tmp.appendingPathComponent("format-sniff.wsz")
        try? HostileZip.make([.init(names: ["main.bmp"], payload: tiff),
                              .init(names: ["cbuttons.bmp"], payload: jpeg),
                              .init(names: ["text.bmp"], payload: makeBMPData(width: 155, height: 74, colour: (1, 1, 1)))])
            .write(to: sniff)
        if let skin = try? SkinLoader.load(url: sniff) {
            c.check("loader: a TIFF main.bmp falls back to Base", !skin.hasOwnSheet(.main)
                    && skin.warnings.contains { $0.hasPrefix("main.bmp") && $0.contains("TIFF") })
            c.check("loader: so does a JPEG cbuttons.bmp", !skin.hasOwnSheet(.cbuttons)
                    && skin.warnings.contains { $0.hasPrefix("cbuttons.bmp") && $0.contains("JPEG") })
            c.check("loader: the real BMP beside them loads", skin.hasOwnSheet(.text))
        } else {
            c.check("the format-sniff skin loads", false)
        }

        // Other extensions are not skin images at all.
        let named = tmp.appendingPathComponent("jpg-named.wsz")
        try? HostileZip.make([.init(names: ["main.jpg"], payload: jpeg), .init(names: ["titlebar.tif"], payload: tiff),
                              .init(names: ["text.gif"], payload: gif)]).write(to: named)
        c.check("a skin of only .jpg/.tif/.gif sheets is no skin", (try? SkinLoader.load(url: named)) == nil)
    }

    // MARK: - 4. Folders and archives: what is a skin, and what an install copies

    private static func folderRules(_ c: Checker, tmp: URL) {
        c.section("skin input: folder skins are their own top level; installs are bounded (A8)")
        let fm = FileManager.default
        func folder(_ name: String, in parent: URL? = nil) -> URL {
            let url = (parent ?? tmp).appendingPathComponent(name, isDirectory: true)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let top = folder("TopLevel")
        try? mainBMP.write(to: top.appendingPathComponent("MAIN.BMP"))
        try? makeBMPData(width: 155, height: 74, colour: (3, 3, 3)).write(to: folder("extras", in: top).appendingPathComponent("text.bmp"))
        c.check("a folder with a sheet at the top is a skin", SkinCatalog.isSkinURL(top))
        if let skin = try? SkinLoader.load(url: top) {
            c.check("its sheet loads", skin.hasOwnSheet(.main))
            c.check("a sheet in a subfolder is not searched for", !skin.hasOwnSheet(.text))
        } else {
            c.check("the top-level folder skin loads", false)
        }

        let holder = folder("HoldsSkins")
        try? mainBMP.write(to: folder("Inner", in: holder).appendingPathComponent("main.bmp"))
        c.check("a folder whose sheets are only in subfolders is not a skin", !SkinCatalog.isSkinURL(holder))
        c.check("and does not load as one", (try? SkinLoader.load(url: holder)) == nil)

        let textOnly = folder("TextOnly")
        try? Data("0,0,0\n".utf8).write(to: textOnly.appendingPathComponent("viscolor.txt"))
        c.check("text files alone are not a skin", !SkinCatalog.isSkinURL(textOnly) && (try? SkinLoader.load(url: textOnly)) == nil)

        let loose = tmp.appendingPathComponent("notes.txt")
        try? Data("hello".utf8).write(to: loose)
        c.check("a loose file that is not an archive is not a skin", !SkinCatalog.isSkinURL(loose))

        // An archive with no sheet in it: a clean error, and nothing installed.
        let skins = folder("Installed")
        func installed() -> [String] { ((try? fm.contentsOfDirectory(atPath: skins.path)) ?? []).sorted() }
        let noSheet = tmp.appendingPathComponent("Readme Only.zip")
        try? HostileZip.make([.init(names: ["readme.txt"], payload: Data("hi".utf8)),
                              .init(names: ["viscolor.txt"], payload: Data("1,1,1\n".utf8))]).write(to: noSheet)
        c.check("a .zip is accepted for a try", SkinCatalog.isSkinURL(noSheet))
        c.check("but one without a sheet does not load", (try? SkinLoader.load(url: noSheet)) == nil)
        c.check("and is not installed", (try? SkinCatalog.install(noSheet, into: skins)) == nil && installed().isEmpty)

        // The install destination itself, and any folder holding it, is refused outright - even
        // when it looks like a skin - and nothing is copied.
        let parent = folder("AppSupport")
        let dest = folder("Skins", in: parent)
        try? mainBMP.write(to: parent.appendingPathComponent("main.bmp"))
        try? mainBMP.write(to: dest.appendingPathComponent("main.bmp"))
        func contents(_ url: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }
        func refusal(_ source: URL) -> Bool {
            do {
                _ = try SkinCatalog.install(source, into: dest)
                return false
            } catch SkinCatalog.InstallError.containsSkinsFolder {
                return true
            } catch {
                return false
            }
        }
        c.check("installing the skins folder into itself is refused", refusal(dest))
        c.check("so is installing a folder that holds it", refusal(parent))
        let alias = tmp.appendingPathComponent("alias-to-appsupport")
        try? fm.createSymbolicLink(at: alias, withDestinationURL: parent)
        c.check("so is a symlink to one", refusal(alias))
        c.equal("and nothing was copied", contents(dest), ["main.bmp"])
        c.equal("into the parent either", contents(parent), ["Skins", "main.bmp"])

        // A good folder: only the files the loader reads, from the top level, within their caps.
        let source = folder("Tidy")
        try? mainBMP.write(to: source.appendingPathComponent("main.bmp"))
        try? Data("9,9,9\n".utf8).write(to: source.appendingPathComponent("VISCOLOR.TXT"))
        try? Data("notes".utf8).write(to: source.appendingPathComponent("readme.md"))
        try? Data("notes".utf8).write(to: source.appendingPathComponent("readme.txt"))
        try? mainBMP.write(to: folder("nested", in: source).appendingPathComponent("eqmain.bmp"))
        sparseFile(source.appendingPathComponent("region.txt"), size: SkinLoader.maximumTextBytes + 1)
        let result = try? SkinCatalog.install(source, into: skins)
        c.equal("a folder installs under its own name", result?.url.lastPathComponent, "Tidy")
        c.equal("with only the top-level files the loader reads, each within its cap",
                contents(skins.appendingPathComponent("Tidy")), ["VISCOLOR.TXT", "main.bmp"])
        c.equal("and no staging copy left over", installed(), ["Tidy"])
    }

    // MARK: - 7. Windows separators

    private static func backslashNames(_ c: Checker, tmp: URL) {
        c.section("skin input: archive names written with \\ (A8)")
        let url = tmp.appendingPathComponent("backslash.wsz")
        try? HostileZip.make([.init(names: ["My Skin\\MAIN.BMP"], payload: mainBMP),
                              .init(names: ["My Skin\\sub\\text.bmp"], payload: makeBMPData(width: 155, height: 74, colour: (5, 5, 5))),
                              .init(names: ["My Skin\\viscolor.txt"], payload: Data("7,8,9\n".utf8)),
                              .init(names: ["My Skin\\"], payload: Data())]).write(to: url)
        if let skin = try? SkinLoader.load(url: url) {
            c.check("a sheet behind a \\ prefix is found", skin.hasOwnSheet(.main))
            c.check("so is one two folders down", skin.hasOwnSheet(.text))
            c.check("and the text files", skin.visColors.rgb[0] == (7, 8, 9))
        } else {
            c.check("the backslash archive loads", false)
        }
        if let archive = try? ZipArchive(url: url) {
            c.check("a name ending in \\ is a directory entry", !archive.entries.contains { $0.name == "My Skin\\" })
        }
    }

    // MARK: - 6. A skin that launches the app

    private static func launchDocuments(_ c: Checker, tmp: URL) {
        c.section("skin input: a skin opened before the app is ready waits for it")
        let wsz = tmp.appendingPathComponent("Launch.wsz")
        try? HostileZip.make([.init(names: ["main.bmp"], payload: mainBMP)]).write(to: wsz)
        let other = tmp.appendingPathComponent("letter.txt")
        try? Data("x".utf8).write(to: other)

        var pending = PendingSkinOpen()
        c.check("before launch completes, the skin is not applied", pending.receive([other, wsz], ready: false) == nil)
        c.equal("it is queued", pending.queued, wsz)
        c.equal("and handed over once the controller starts", pending.takeQueued(), wsz)
        c.check("exactly once", pending.takeQueued() == nil)
        c.check("a non-skin is never queued", pending.receive([other], ready: false) == nil && pending.queued == nil)
        c.equal("once running, a skin is applied at once", pending.receive([wsz], ready: true), wsz)
        c.check("and nothing is left queued", pending.queued == nil)
    }

    // MARK: - Helpers

    /// A file of `size` bytes that takes no space: the loader must refuse it from its size alone.
    private static func sparseFile(_ url: URL, size: Int) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        if let h = FileHandle(forWritingAtPath: url.path) {
            try? h.truncate(atOffset: UInt64(size))
            try? h.close()
        }
    }

    private static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// `image` drawn at 2x over an opaque colour through the renderers' own canvas, as bytes.
    private static func rendered(_ image: CGImage) -> Data? {
        guard let canvas = SkinCanvas.offscreen(width: image.width, height: image.height, scale: 2) else { return nil }
        canvas.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height), CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        canvas.draw(image, at: 0, 0)
        return canvas.makeImage()?.dataProvider?.data as Data?
    }

    /// A BMP of deterministic noise: 24- or 32-bit (padding byte 0, as Windows writes it), or 8-bit
    /// with a 256-colour palette.
    private static func noiseBMP(width: Int, height: Int, bitsPerPixel: Int) -> Data {
        var seed: UInt32 = 0x1234_5678
        func next() -> UInt8 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: seed >> 24)
        }
        let paletteBytes = bitsPerPixel == 8 ? 256 * 4 : 0
        let rowBytes = ((width * bitsPerPixel / 8) + 3) & ~3
        var d = Data()
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: [0x42, 0x4D])
        u32(54 + paletteBytes + rowBytes * height); u16(0); u16(0); u32(54 + paletteBytes)
        u32(40); u32(width); u32(height); u16(1); u16(bitsPerPixel); u32(0); u32(rowBytes * height)
        u32(2835); u32(2835); u32(bitsPerPixel == 8 ? 256 : 0); u32(0)
        if bitsPerPixel == 8 { for _ in 0..<256 { d.append(contentsOf: [next(), next(), next(), 0]) } }
        for _ in 0..<height {
            var row = Data()
            for _ in 0..<width {
                switch bitsPerPixel {
                case 8: row.append(next())
                case 32: row.append(contentsOf: [next(), next(), next(), 0])
                default: row.append(contentsOf: [next(), next(), next()])
                }
            }
            while row.count < rowBytes { row.append(0) }
            d.append(row)
        }
        return d
    }
}

/// A zip writer for hostile archives, used only by `--selftest`: real deflate, forged sizes, and
/// several central-directory names sharing one member (an overlapping bomb: 65 KB on disk, 16
/// names, 64 MiB each). CRCs are left zero; the reader does not check them.
enum HostileZip {

    struct Member {
        /// Every central-directory name that points at this one member.
        var names: [String]
        var payload: Data
        var deflate: Bool = true
        /// Forged uncompressed size for the central directory; the true one when nil.
        var declaredSize: Int?
    }

    static func make(_ members: [Member]) -> Data {
        var out = Data()
        var central = Data()
        var count = 0
        for member in members {
            let body = member.deflate && !member.payload.isEmpty ? (rawDeflate(member.payload) ?? member.payload) : member.payload
            let method: UInt16 = member.deflate && !member.payload.isEmpty ? 8 : 0
            let declared = UInt32(member.declaredSize ?? member.payload.count)
            let offset = UInt32(out.count)
            let localName = Data((member.names.first ?? "x").utf8)
            append(&out, 0x0403_4B50, 32); append(&out, 20, 16); append(&out, 0x0800, 16); append(&out, UInt32(method), 16)
            append(&out, 0, 16); append(&out, 0, 16); append(&out, 0, 32)
            append(&out, UInt32(body.count), 32); append(&out, declared, 32)
            append(&out, UInt32(localName.count), 16); append(&out, 0, 16)
            out.append(localName)
            out.append(body)
            for name in member.names {
                let nameBytes = Data(name.utf8)
                append(&central, 0x0201_4B50, 32); append(&central, 20, 16); append(&central, 20, 16)
                append(&central, 0x0800, 16); append(&central, UInt32(method), 16)
                append(&central, 0, 16); append(&central, 0, 16); append(&central, 0, 32)
                append(&central, UInt32(body.count), 32); append(&central, declared, 32)
                append(&central, UInt32(nameBytes.count), 16)
                append(&central, 0, 16); append(&central, 0, 16); append(&central, 0, 16); append(&central, 0, 16)
                append(&central, 0, 32); append(&central, offset, 32)
                central.append(nameBytes)
                count += 1
            }
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        append(&out, 0x0605_4B50, 32); append(&out, 0, 16); append(&out, 0, 16)
        append(&out, UInt32(count), 16); append(&out, UInt32(count), 16)
        append(&out, UInt32(central.count), 32); append(&out, cdOffset, 32); append(&out, 0, 16)
        return out
    }

    /// Raw DEFLATE, the inverse of `ZipArchive.inflate`.
    static func rawDeflate(_ input: Data) -> Data? {
        let capacity = input.count + input.count / 8 + 1_024
        var out = Data(count: capacity)
        let written: Int = out.withUnsafeMutableBytes { dst -> Int in
            guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return input.withUnsafeBytes { src -> Int in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(dstBase, capacity, srcBase, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        out.removeSubrange(written..<capacity)
        return out
    }

    private static func append(_ d: inout Data, _ v: UInt32, _ bits: Int) {
        if bits == 16 {
            withUnsafeBytes(of: UInt16(truncatingIfNeeded: v).littleEndian) { d.append(contentsOf: $0) }
        } else {
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
    }
}
