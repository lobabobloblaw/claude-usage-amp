import Foundation

/// One row of the pricing table: a lower-cased substring to look for in the model id, and the
/// per-million-token prices in USD.
public struct ModelPrice: Equatable {
    public var match: String
    public var input: Double
    public var output: Double
    /// Cache-read price per million tokens, for a model whose cache reads are not the general
    /// 0.1x input (SPEC 4.2, amendment A4: Claude Fable 5.1 reads at $0.25 against $10 input).
    /// nil means the general rule; see `PricingTable.price(for:)` for how a nil row is resolved.
    public var explicitCacheRead: Double?

    public init(match: String, input: Double, output: Double, cacheRead: Double? = nil) {
        self.match = match
        self.input = input
        self.output = output
        self.explicitCacheRead = cacheRead
    }

    /// The general cache-read rule: 0.1x input.
    public static let defaultCacheReadRatio = 0.1

    /// Cache write, 5 minute TTL.
    public var cacheWrite5m: Double { input * 1.25 }
    /// Cache write, 1 hour TTL.
    public var cacheWrite1h: Double { input * 2 }
    /// Cache read: the explicit price when the row has one, else 0.1x input.
    public var cacheRead: Double { explicitCacheRead ?? input * ModelPrice.defaultCacheReadRatio }
}

/// Ordered list of price rows; first substring match wins, with a fallback for everything else.
public struct PricingTable: Equatable {
    public var rows: [ModelPrice]
    public var fallback: ModelPrice

    public init(rows: [ModelPrice], fallback: ModelPrice = ModelPrice(match: "*", input: 3, output: 15)) {
        self.rows = rows
        self.fallback = fallback
    }

    /// SPEC 4.2. First substring match wins, so a specific row must come before the general row
    /// it would otherwise be shadowed by (`fable-5-1` before `fable`; the self-test checks that
    /// every row is reachable).
    public static let builtIn = PricingTable(rows: [
        // Claude Fable 5.1 cache reads cost $0.25/MTok, 0.025x input, not the general 0.1x.
        // Claude Fable 5 (`claude-fable-5`, and its dated ids) falls through to `fable`.
        ModelPrice(match: "fable-5-1", input: 10, output: 50, cacheRead: 0.25),
        ModelPrice(match: "fable", input: 10, output: 50),
        // Claude Mythos 5.1's cache-read rate is unannounced: general rule until it is.
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

    /// The effective price for a model id: the first row whose `match` is a substring of the
    /// lower-cased id (else the fallback), with its cache-read price resolved.
    ///
    /// A row without an explicit `cacheRead` does not simply mean 0.1x input. It means "this row's
    /// input price times the cache-read ratio the built-in table has for this model id" — 0.1 for
    /// every model except Claude Fable 5.1, whose ratio is 0.025. That is what keeps a
    /// `pricing.json` written before amendment A4 (no `cacheRead` field, no `fable-5-1` row, its
    /// generic `fable` row catching Fable 5.1) from pricing Fable 5.1 cache reads 4x too high, while
    /// still honouring whatever input price the user put in that row. A row that gives `cacheRead`
    /// explicitly always wins.
    public func price(for model: String) -> ModelPrice {
        let m = model.lowercased()
        var p = rows.first { m.contains($0.match) } ?? fallback
        guard p.explicitCacheRead == nil else { return p }
        let reference = PricingTable.builtIn.rows.first { m.contains($0.match) } ?? PricingTable.builtIn.fallback
        if let referenceRead = reference.explicitCacheRead, reference.input > 0 {
            p.explicitCacheRead = p.input * referenceRead / reference.input
        }
        return p
    }

    // MARK: - pricing.json

    /// Parse the user-overridable file. Returns nil when the file is missing or unusable, in which
    /// case the caller keeps the built-in table.
    ///
    /// Each row is `{match, input, output}` plus an optional `cacheRead` (USD per million tokens).
    /// A `cacheRead` that is not a finite, non-negative number is ignored rather than dropping the
    /// row, so a typo there cannot re-route the model to some later, differently priced row; the
    /// row then gets the cache-read rule described at `price(for:)`.
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
            var cacheRead: Double?
            if let c = JSONNumber.double(d["cacheRead"]), c.isFinite, c >= 0 { cacheRead = c }
            let lower = match.lowercased()
            if lower == "*" || lower == "default" {
                fallback = ModelPrice(match: "*", input: input, output: output, cacheRead: cacheRead)
            } else {
                rows.append(ModelPrice(match: lower, input: input, output: output, cacheRead: cacheRead))
            }
        }
        guard !rows.isEmpty else { return nil }
        return PricingTable(rows: rows, fallback: fallback)
    }

    public func jsonData() -> Data {
        var s = "{\n  \"_comment\": \"Tokenamp pricing, USD per million tokens. Ordered; the first row whose 'match' is a substring of the lower-cased model id wins. Cache write 5m = 1.25x input, cache write 1h = 2x input. Cache read is the row's 'cacheRead' when given; a row without it uses input x the model's built-in cache-read ratio, which is 0.1 for every model except Claude Fable 5.1 (0.025, i.e. $0.25 at $10 input). The row matching \\\"*\\\" is the fallback.\",\n  \"models\": [\n"
        var parts: [String] = []
        for r in rows + [ModelPrice(match: "*", input: fallback.input, output: fallback.output,
                                    cacheRead: fallback.explicitCacheRead)] {
            var row = "    { \"match\": \"\(r.match)\", \"input\": \(trim(r.input)), \"output\": \(trim(r.output))"
            if let c = r.explicitCacheRead { row += ", \"cacheRead\": \(trim(c))" }
            parts.append(row + " }")
        }
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
