import Foundation

/// One row of the pricing table: a lower-cased substring to look for in the model id, and the
/// per-million-token input/output prices in USD.
public struct ModelPrice: Equatable {
    public var match: String
    public var input: Double
    public var output: Double

    public init(match: String, input: Double, output: Double) {
        self.match = match
        self.input = input
        self.output = output
    }

    /// Cache write, 5 minute TTL.
    public var cacheWrite5m: Double { input * 1.25 }
    /// Cache write, 1 hour TTL.
    public var cacheWrite1h: Double { input * 2 }
    public var cacheRead: Double { input * 0.1 }
}

/// Ordered list of price rows; first substring match wins, with a fallback for everything else.
public struct PricingTable: Equatable {
    public var rows: [ModelPrice]
    public var fallback: ModelPrice

    public init(rows: [ModelPrice], fallback: ModelPrice = ModelPrice(match: "*", input: 3, output: 15)) {
        self.rows = rows
        self.fallback = fallback
    }

    /// SPEC 4.2.
    public static let builtIn = PricingTable(rows: [
        ModelPrice(match: "fable", input: 10, output: 50),
        ModelPrice(match: "mythos", input: 10, output: 50),
        ModelPrice(match: "opus-5", input: 5, output: 25),
        ModelPrice(match: "opus-4-5", input: 5, output: 25),
        ModelPrice(match: "opus-4-6", input: 5, output: 25),
        ModelPrice(match: "opus-4-7", input: 5, output: 25),
        ModelPrice(match: "opus-4-8", input: 5, output: 25),
        ModelPrice(match: "opus", input: 15, output: 75),
        ModelPrice(match: "sonnet-5", input: 2, output: 10),
        ModelPrice(match: "sonnet", input: 3, output: 15),
        ModelPrice(match: "haiku-4", input: 1, output: 5),
        ModelPrice(match: "haiku-3-5", input: 0.8, output: 4),
        ModelPrice(match: "haiku", input: 0.25, output: 1.25),
    ])

    public func price(for model: String) -> ModelPrice {
        let m = model.lowercased()
        for row in rows where m.contains(row.match) { return row }
        return fallback
    }

    // MARK: - pricing.json

    /// Parse the user-overridable file. Returns nil when the file is missing or unusable, in which
    /// case the caller keeps the built-in table.
    public static func parse(_ data: Data) -> PricingTable? {
        guard let any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var array: [Any]?
        if let a = any as? [Any] { array = a }
        if let d = any as? [String: Any] { array = (d["models"] as? [Any]) ?? (d["rows"] as? [Any]) }
        guard let list = array else { return nil }
        var rows: [ModelPrice] = []
        var fallback = ModelPrice(match: "*", input: 3, output: 15)
        for item in list {
            guard let d = item as? [String: Any],
                  let match = d["match"] as? String,
                  let input = JSONNumber.double(d["input"]),
                  let output = JSONNumber.double(d["output"]),
                  // A hand-edited file can legally contain `1e999`; an infinite price would turn
                  // every cost in the app into `inf`.
                  input.isFinite, output.isFinite, input >= 0, output >= 0 else { continue }
            let lower = match.lowercased()
            if lower == "*" || lower == "default" {
                fallback = ModelPrice(match: "*", input: input, output: output)
            } else {
                rows.append(ModelPrice(match: lower, input: input, output: output))
            }
        }
        guard !rows.isEmpty else { return nil }
        return PricingTable(rows: rows, fallback: fallback)
    }

    public func jsonData() -> Data {
        var s = "{\n  \"_comment\": \"Tokenamp pricing, USD per million tokens. Ordered; the first row whose 'match' is a substring of the lower-cased model id wins. Cache write 5m = 1.25x input, cache write 1h = 2x input, cache read = 0.1x input. The row matching \\\"*\\\" is the fallback.\",\n  \"models\": [\n"
        var parts: [String] = []
        for r in rows {
            parts.append("    { \"match\": \"\(r.match)\", \"input\": \(trim(r.input)), \"output\": \(trim(r.output)) }")
        }
        parts.append("    { \"match\": \"*\", \"input\": \(trim(fallback.input)), \"output\": \(trim(fallback.output)) }")
        s += parts.joined(separator: ",\n")
        s += "\n  ]\n}\n"
        return Data(s.utf8)
    }

    private func trim(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }

    /// Load `pricing.json`, writing the default file on first run.
    public static func loadOrCreateDefault(at url: URL = TokenampPaths.pricingURL) -> PricingTable {
        if let data = try? Data(contentsOf: url), let table = parse(data) { return table }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? TokenampPaths.writeAtomically(builtIn.jsonData(), to: url)
        }
        return builtIn
    }
}

/// Table plus a memoised per-model lookup — the aggregator prices tens of thousands of events per
/// rebuild, so the substring walk must not happen per event.
public final class PricingResolver {
    public private(set) var table: PricingTable
    private var cache: [String: ModelPrice] = [:]

    public init(table: PricingTable = .builtIn) { self.table = table }

    public func setTable(_ t: PricingTable) {
        guard t != table else { return }
        table = t
        cache.removeAll(keepingCapacity: true)
    }

    public func price(for model: String) -> ModelPrice {
        if let p = cache[model] { return p }
        let p = table.price(for: model)
        cache[model] = p
        return p
    }

    /// API-list-price equivalent for one API response.
    public func cost(model: String, input: Int, output: Int, cacheWrite5m: Int, cacheWrite1h: Int, cacheRead: Int) -> Double {
        let p = price(for: model)
        let total = Double(input) * p.input
            + Double(output) * p.output
            + Double(cacheWrite5m) * p.cacheWrite5m
            + Double(cacheWrite1h) * p.cacheWrite1h
            + Double(cacheRead) * p.cacheRead
        return total / 1_000_000
    }
}

enum JSONNumber {
    static func double(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    /// `Int(Double)` **traps** on infinity, NaN and anything outside `Int`'s range, and a transcript
    /// line may legally contain `1e400` in a numeric field. Clamping (rather than converting) keeps
    /// one malformed line from taking the process down.
    @inline(__always) static func clampToInt(_ d: Double) -> Int {
        guard d.isFinite else { return 0 }
        if d >= 9.2e18 { return Int.max }
        if d <= -9.2e18 { return Int.min }
        return Int(d)
    }

    static func int(_ any: Any?) -> Int {
        switch any {
        case let i as Int: return i
        case let d as Double: return clampToInt(d)
        case let n as NSNumber: return clampToInt(n.doubleValue)
        case let s as String: return Int(s) ?? 0
        default: return 0
        }
    }
}
