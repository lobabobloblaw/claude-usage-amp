import CoreGraphics
import Foundation

// Lenient parsers for the three plain-text files a classic skin can carry. Every one of them is
// hand-edited by skin authors, so all of them tolerate CRLF, stray whitespace, comments, missing
// keys, Latin-1 bytes and general sloppiness. None of them ever throws: a broken file degrades to
// defaults plus a warning.

/// Bytes -> String with a UTF-8 attempt and a Latin-1 fallback (classic skins predate UTF-8).
func decodeSkinText(_ data: Data) -> String {
    if let s = String(data: data, encoding: .utf8) { return s }
    return String(data: data, encoding: .isoLatin1) ?? ""
}

/// Split on CR, LF or CRLF.
///
/// Note: in Swift a CRLF pair is a *single* `Character`, so splitting on `"\n"` alone silently
/// treats a whole CRLF file as one line. Normalise first.
func skinTextLines(_ text: String) -> [String] {
    text.replacingOccurrences(of: "\r\n", with: "\n")
        .split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
        .map(String.init)
}

// MARK: - viscolor.txt

/// The 24 visualizer colours.
///
/// 0 = background, 1 = background dots, 2...17 = spectrum bars top to bottom,
/// 18...22 = oscilloscope (18 brightest/centre), 23 = spectrum peak caps.
public struct VisColors: Equatable {
    public var rgb: [(r: Int, g: Int, b: Int)]

    public static let count = 24

    public init(rgb: [(r: Int, g: Int, b: Int)]) {
        var v = rgb
        while v.count < VisColors.count { v.append(VisColors.defaultRGB[v.count]) }
        self.rgb = Array(v.prefix(VisColors.count))
    }

    public static func == (a: VisColors, b: VisColors) -> Bool {
        a.rgb.count == b.rgb.count && zip(a.rgb, b.rgb).allSatisfy { $0 == $1 }
    }

    /// Winamp's stock palette, used when viscolor.txt is missing or unreadable.
    public static let defaultRGB: [(r: Int, g: Int, b: Int)] = [
        (0, 0, 0), (24, 33, 41),
        (239, 239, 239), (206, 226, 230), (181, 217, 224), (157, 208, 217), (132, 199, 211),
        (108, 190, 204), (83, 181, 198), (59, 172, 191), (34, 163, 185), (24, 152, 173),
        (18, 139, 158), (13, 125, 142), (9, 111, 126), (5, 97, 110), (2, 83, 94), (0, 69, 78),
        (0, 200, 0), (0, 180, 0), (0, 160, 0), (0, 140, 0), (0, 120, 0),
        (255, 255, 255),
    ]

    public static let fallback = VisColors(rgb: defaultRGB)

    public func color(_ index: Int) -> CGColor {
        let c = rgb[min(max(index, 0), VisColors.count - 1)]
        return CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }

    /// One line per colour: `r,g,b` with anything after the three integers treated as a comment.
    /// Blank lines and lines starting with `//` or `;` or `#` are skipped.
    public static func parse(_ data: Data) -> VisColors {
        var out: [(r: Int, g: Int, b: Int)] = []
        for raw in skinTextLines(decodeSkinText(data)) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("//") || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            // The first three integer runs on the line are r, g, b; the rest is a comment.
            var nums: [Int] = []
            var cur = ""
            for ch in line {
                if ch.isASCII && ch.isNumber {
                    cur.append(ch)
                } else if !cur.isEmpty {
                    nums.append(Int(cur) ?? 0)
                    cur = ""
                    if nums.count == 3 { break }
                }
            }
            if !cur.isEmpty, nums.count < 3 { nums.append(Int(cur) ?? 0) }
            guard nums.count >= 3 else { continue }
            out.append((min(255, nums[0]), min(255, nums[1]), min(255, nums[2])))
            if out.count == count { break }
        }
        guard !out.isEmpty else { return .fallback }
        return VisColors(rgb: out)
    }
}

// MARK: - pledit.txt

public struct PleditColors: Equatable {
    public var normal: CGColor
    public var current: CGColor
    public var normalBG: CGColor
    public var selectedBG: CGColor
    public var fontName: String

    public static let fallback = PleditColors(
        normal: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
        current: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        normalBG: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
        selectedBG: CGColor(srgbRed: 0, green: 0, blue: 0.7, alpha: 1),
        fontName: "Arial")

    public static func == (a: PleditColors, b: PleditColors) -> Bool {
        a.fontName == b.fontName
            && a.normal == b.normal && a.current == b.current
            && a.normalBG == b.normalBG && a.selectedBG == b.selectedBG
    }

    public static func parse(_ data: Data) -> PleditColors {
        var out = PleditColors.fallback
        let ini = INIFile.parse(data)
        let text = ini.section("Text")
        if let c = parseHexColor(text["normal"]) { out.normal = c }
        if let c = parseHexColor(text["current"]) { out.current = c }
        if let c = parseHexColor(text["normalbg"]) { out.normalBG = c }
        if let c = parseHexColor(text["selectedbg"]) { out.selectedBG = c }
        if let f = text["font"], !f.isEmpty { out.fontName = f }
        return out
    }

    /// `#RRGGBB`, `RRGGBB`, `#RGB` — anything else is nil.
    static func parseHexColor(_ s: String?) -> CGColor? {
        guard var t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        if t.hasPrefix("#") { t.removeFirst() }
        t = t.filter { $0.isHexDigit }
        if t.count == 3 {
            t = t.map { "\($0)\($0)" }.joined()
        }
        guard t.count >= 6 else { return nil }
        let hex = String(t.prefix(6))
        guard let v = UInt32(hex, radix: 16) else { return nil }
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - a tiny lenient INI reader

public struct INIFile {
    /// section name (lowercased) -> key (lowercased) -> value
    public private(set) var sections: [String: [String: String]] = [:]

    public func section(_ name: String) -> [String: String] {
        sections[name.lowercased()] ?? [:]
    }

    public static func parse(_ data: Data) -> INIFile {
        parse(text: decodeSkinText(data))
    }

    public static func parse(text: String) -> INIFile {
        var out = INIFile()
        var current = ""
        for raw in skinTextLines(text) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix(";") || line.hasPrefix("//") { continue }
            if let hash = line.firstIndex(of: "#"), line.hasPrefix("#") == false, !line.contains("=") {
                line = String(line[line.startIndex..<hash]).trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
            }
            if line.hasPrefix("[") {
                let name = line.drop(while: { $0 == "[" }).prefix(while: { $0 != "]" })
                current = name.trimmingCharacters(in: .whitespaces).lowercased()
                if out.sections[current] == nil { out.sections[current] = [:] }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            out.sections[current, default: [:]][key] = value
        }
        return out
    }
}

// MARK: - region.txt

public enum SkinRegionKind: String, CaseIterable {
    case normal = "Normal"
    case windowShade = "WindowShade"
    case equalizer = "Equalizer"
    case equalizerWS = "EqualizerWS"
}

/// The union of polygons that make up a window's visible shape.
public struct SkinRegion: Equatable {
    public var polygons: [[CGPoint]]

    public static func == (a: SkinRegion, b: SkinRegion) -> Bool {
        a.polygons.count == b.polygons.count
            && zip(a.polygons, b.polygons).allSatisfy { $0 == $1 }
    }

    public var isEmpty: Bool { polygons.allSatisfy { $0.count < 3 } }

    /// Build a CGPath in skin-pixel coordinates (y down), ready to be used as a clip.
    public func path() -> CGPath {
        let p = CGMutablePath()
        for poly in polygons where poly.count >= 3 {
            p.move(to: poly[0])
            for pt in poly.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
        }
        return p
    }
}

public struct SkinRegions {
    public private(set) var regions: [SkinRegionKind: SkinRegion] = [:]

    public subscript(kind: SkinRegionKind) -> SkinRegion? { regions[kind] }

    public static func parse(_ data: Data) -> SkinRegions {
        var out = SkinRegions()
        let ini = INIFile.parse(data)
        for kind in SkinRegionKind.allCases {
            let sec = ini.section(kind.rawValue)
            guard !sec.isEmpty else { continue }
            let counts = ints(sec["numpoints"])
            let coords = ints(sec["pointlist"])
            guard !counts.isEmpty, coords.count >= 2 else { continue }
            var polys: [[CGPoint]] = []
            var idx = 0
            for n in counts where n > 0 {
                var poly: [CGPoint] = []
                for _ in 0..<n {
                    guard idx + 1 < coords.count else { break }
                    poly.append(CGPoint(x: CGFloat(coords[idx]), y: CGFloat(coords[idx + 1])))
                    idx += 2
                }
                if poly.count >= 3 { polys.append(poly) }
            }
            if !polys.isEmpty { out.regions[kind] = SkinRegion(polygons: polys) }
        }
        return out
    }

    private static func ints(_ s: String?) -> [Int] {
        guard let s else { return [] }
        var out: [Int] = []
        var cur = ""
        var negative = false
        for ch in s {
            if ch.isNumber {
                cur.append(ch)
            } else {
                if !cur.isEmpty { out.append((negative ? -1 : 1) * (Int(cur) ?? 0)); cur = ""; negative = false }
                negative = (ch == "-")
            }
        }
        if !cur.isEmpty { out.append((negative ? -1 : 1) * (Int(cur) ?? 0)) }
        return out
    }
}
