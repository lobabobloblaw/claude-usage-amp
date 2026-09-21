import Foundation

/// `claude-fable-5-1` -> `FABLE 5.1`, `claude-haiku-4-5-20251001` -> `HAIKU 4.5` (SPEC 4.2).
///
/// Rule: drop everything up to and including a `claude-` prefix, drop a trailing 8-digit date,
/// upper-case the first non-numeric component as the family and join the remaining numeric
/// components with `.`. Old-style ids (`claude-3-5-sonnet-20241022`) therefore come out as
/// `SONNET 3.5`, which is the reading a human expects.
/// Pure and free of global state: callers that need it per event memoise it themselves (see
/// `Aggregator`), because the scan queue must not share mutable caches with the main thread.
public enum ModelDisplayName {

    public static func of(_ modelID: String) -> String { compute(modelID) }

    static func compute(_ modelID: String) -> String {
        var s = modelID.lowercased()
        if s.isEmpty { return "" }
        if s == "<synthetic>" { return "SYNTHETIC" }
        // Strip vendor routing prefixes such as "us.anthropic.claude-opus-5-v1:0".
        if let r = s.range(of: "claude-") { s = String(s[r.upperBound...]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[s.startIndex..<colon]) }
        // A bracketed variant marker (`claude-opus-5[1m]`) is kept, but out of the number run.
        var bracket = ""
        if let open = s.firstIndex(of: "[") {
            bracket = String(s[open...]).uppercased()
            s = String(s[s.startIndex..<open])
        }
        var parts = s.split(separator: "-").map(String.init)
        // Trailing 8-digit date.
        if let last = parts.last, last.count == 8, last.allSatisfy({ $0.isNumber }) { parts.removeLast() }
        // Trailing "-v1" style revision markers add nothing.
        if let last = parts.last, last.count == 2, last.first == "v", last.last!.isNumber { parts.removeLast() }
        guard !parts.isEmpty else { return modelID.uppercased() }

        let familyIndex = parts.firstIndex { !$0.allSatisfy { $0.isNumber } } ?? 0
        let family = parts[familyIndex].uppercased()
        let numbers = parts.enumerated().filter { $0.offset != familyIndex && $0.element.allSatisfy { $0.isNumber } }.map { $0.element }
        let extras = parts.enumerated()
            .filter { $0.offset != familyIndex && !$0.element.allSatisfy { $0.isNumber } }
            .map { $0.element.uppercased() }

        var out = family
        if !numbers.isEmpty { out += " " + numbers.joined(separator: ".") }
        if !extras.isEmpty { out += " " + extras.joined(separator: " ") }
        if !bracket.isEmpty { out += " " + bracket }
        return out
    }
}
