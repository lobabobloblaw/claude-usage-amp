import Compression
import Foundation

/// A minimal, in-process ZIP reader: parse the central directory, extract stored (method 0) and
/// deflated (method 8) members. No temp files, no shelling out.
///
/// Deliberately narrow: classic `.wsz` skins are plain single-disk zips of a handful of small
/// files. Anything exotic (zip64, encryption, split archives, unsupported methods) is rejected or
/// skipped with a warning rather than guessed at.
public struct ZipArchive {

    public enum Error: Swift.Error, CustomStringConvertible {
        case notAZip
        case zip64Unsupported
        case truncated(String)
        case unsupportedMethod(UInt16, String)
        case decompressionFailed(String)
        case tooLarge(String, Int)

        public var description: String {
            switch self {
            case .notAZip: return "not a zip archive (no end-of-central-directory record)"
            case .zip64Unsupported: return "zip64 archives are not supported"
            case .truncated(let what): return "archive is truncated (\(what))"
            case .unsupportedMethod(let m, let name): return "unsupported compression method \(m) for \(name)"
            case .decompressionFailed(let name): return "could not inflate \(name)"
            case .tooLarge(let name, let n): return "\(name) declares \(n) bytes, more than a skin file may be"
            }
        }
    }

    /// The largest member this reader will allocate for when the caller names no tighter bound: it
    /// stops a hostile archive from making us allocate by *declaring* a four-gigabyte uncompressed
    /// size in its central directory. The skin loader passes a much smaller per-kind bound
    /// (`SkinLoader.byteLimit`), so a skin member never comes near this.
    public static let maximumMemberBytes = 64 << 20

    public struct Entry {
        public let name: String
        public let method: UInt16
        public let flags: UInt16
        public let compressedSize: Int
        public let uncompressedSize: Int
        public let localHeaderOffset: Int
        /// `\` too: PowerShell 5's Compress-Archive writes Windows separators.
        public var isDirectory: Bool { name.hasSuffix("/") || name.hasSuffix("\\") }
        public var isEncrypted: Bool { flags & 0x0001 != 0 }
    }

    public let entries: [Entry]
    /// Entries that were present but could not be offered (encrypted, unknown method).
    public let skipped: [String]
    private let data: Data

    // MARK: - Parsing

    public init(data: Data) throws {
        self.data = data
        guard data.count >= 22 else { throw Error.notAZip }

        // End of central directory: scan backwards over the (max 64 KiB) comment.
        let maxBack = min(data.count, 22 + 0xFFFF)
        var eocd = -1
        var i = data.count - 22
        let lowest = data.count - maxBack
        while i >= lowest {
            if data.u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Error.notAZip }

        let diskEntries = Int(data.u16(eocd + 8))
        let totalEntries = Int(data.u16(eocd + 10))
        let cdSize = Int(data.u32(eocd + 12))
        let cdOffset = Int(data.u32(eocd + 16))

        // Zip64 markers.
        if totalEntries == 0xFFFF || diskEntries == 0xFFFF || cdSize == Int(UInt32.max) || cdOffset == Int(UInt32.max) {
            throw Error.zip64Unsupported
        }
        if eocd >= 20, data.u32(eocd - 20) == 0x0706_4B50 { throw Error.zip64Unsupported }
        guard cdOffset >= 0, cdOffset + cdSize <= data.count else { throw Error.truncated("central directory") }

        var found: [Entry] = []
        var skippedNames: [String] = []
        var p = cdOffset
        var n = 0
        while n < totalEntries {
            guard p + 46 <= data.count, data.u32(p) == 0x0201_4B50 else { break }
            let flags = data.u16(p + 8)
            let method = data.u16(p + 10)
            let cSize = Int(data.u32(p + 20))
            let uSize = Int(data.u32(p + 24))
            let nameLen = Int(data.u16(p + 28))
            let extraLen = Int(data.u16(p + 30))
            let commentLen = Int(data.u16(p + 32))
            let localOffset = Int(data.u32(p + 42))
            guard p + 46 + nameLen <= data.count else { throw Error.truncated("central directory entry name") }
            let nameBytes = data.slice(p + 46, nameLen)
            let utf8Flag = flags & 0x0800 != 0
            let name = ZipArchive.decodeName(nameBytes, utf8: utf8Flag)

            if cSize == Int(UInt32.max) || uSize == Int(UInt32.max) || localOffset == Int(UInt32.max) {
                throw Error.zip64Unsupported
            }
            let entry = Entry(name: name, method: method, flags: flags, compressedSize: cSize,
                              uncompressedSize: uSize, localHeaderOffset: localOffset)
            if entry.isEncrypted || (method != 0 && method != 8) {
                if !entry.isDirectory { skippedNames.append(name) }
            } else if !entry.isDirectory {
                found.append(entry)
            }
            p += 46 + nameLen + extraLen + commentLen
            n += 1
        }
        guard !found.isEmpty || !skippedNames.isEmpty || totalEntries == 0 else { throw Error.notAZip }
        entries = found
        skipped = skippedNames
    }

    public init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    // MARK: - Extraction

    public func extract(_ entry: Entry) throws -> Data {
        try extract(entry, limit: ZipArchive.maximumMemberBytes)
    }

    /// Extract one member, refused before a byte of it is copied or inflated if it could come out
    /// larger than `limit`. The central directory's declared size is attacker-controlled and
    /// decides how big a buffer we allocate, so it must fit; so must a stored member's payload,
    /// which is copied as is. A deflate stream is inflated into a buffer of exactly the declared
    /// size, so one that would inflate to more than it declared stops there instead of growing.
    public func extract(_ entry: Entry, limit: Int) throws -> Data {
        guard entry.uncompressedSize <= limit else { throw Error.tooLarge(entry.name, entry.uncompressedSize) }
        if entry.method == 0, entry.compressedSize > limit {
            throw Error.tooLarge(entry.name, entry.compressedSize)
        }

        // The local header repeats the name/extra lengths; its sizes may be zero when a data
        // descriptor follows, so always trust the central directory's sizes.
        let lh = entry.localHeaderOffset
        guard lh + 30 <= data.count, data.u32(lh) == 0x0403_4B50 else {
            throw Error.truncated("local header for \(entry.name)")
        }
        let nameLen = Int(data.u16(lh + 26))
        let extraLen = Int(data.u16(lh + 28))
        let start = lh + 30 + nameLen + extraLen
        guard start + entry.compressedSize <= data.count else {
            throw Error.truncated("payload for \(entry.name)")
        }

        switch entry.method {
        case 0:
            return data.slice(start, entry.compressedSize)
        case 8:
            if entry.uncompressedSize == 0 { return Data() }
            // Inflated straight out of the (memory-mapped) archive: no copy of the compressed bytes.
            guard let out = ZipArchive.inflate(data.view(start, entry.compressedSize), expected: entry.uncompressedSize) else {
                throw Error.decompressionFailed(entry.name)
            }
            return out
        default:
            throw Error.unsupportedMethod(entry.method, entry.name)
        }
    }

    public func data(for name: String) throws -> Data? {
        guard let e = entries.first(where: { $0.name == name }) else { return nil }
        return try extract(e)
    }

    /// Raw DEFLATE (no zlib wrapper) via the Compression framework: `COMPRESSION_ZLIB`.
    static func inflate(_ input: Data, expected: Int) -> Data? {
        guard expected > 0 else { return Data() }
        // Some writers under-report; give the buffer a little slack and trust the byte count back.
        let capacity = expected
        var out = Data(count: capacity)
        let written: Int = out.withUnsafeMutableBytes { dst -> Int in
            guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return input.withUnsafeBytes { src -> Int in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, capacity, srcBase, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        if written < capacity { out.removeSubrange(written..<capacity) }
        return out
    }

    private static func decodeName(_ bytes: Data, utf8: Bool) -> String {
        if utf8, let s = String(data: bytes, encoding: .utf8) { return s }
        if let s = String(data: bytes, encoding: .utf8) { return s }
        // CP437 is close enough to Latin-1 for the ASCII file names classic skins use.
        return String(data: bytes, encoding: .isoLatin1) ?? ""
    }
}

// MARK: - Little-endian readers that never trap on a short buffer

private extension Data {
    func byte(_ i: Int) -> UInt8 {
        guard i >= 0, i < count else { return 0 }
        return self[index(startIndex, offsetBy: i)]
    }

    func u16(_ i: Int) -> UInt16 {
        UInt16(byte(i)) | (UInt16(byte(i + 1)) << 8)
    }

    func u32(_ i: Int) -> UInt32 {
        UInt32(byte(i)) | (UInt32(byte(i + 1)) << 8) | (UInt32(byte(i + 2)) << 16) | (UInt32(byte(i + 3)) << 24)
    }

    func slice(_ offset: Int, _ length: Int) -> Data {
        Data(view(offset, length))
    }

    /// The same bytes as `slice`, sharing this buffer instead of copying it.
    func view(_ offset: Int, _ length: Int) -> Data {
        guard offset >= 0, length > 0, offset + length <= count else { return Data() }
        let a = index(startIndex, offsetBy: offset)
        let b = index(a, offsetBy: length)
        return self[a..<b]
    }
}
