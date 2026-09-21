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
    /// Price multiplier for fast-mode responses (`usage.speed == "fast"`; SPEC 4.2, amendment A5).
    /// It scales every rate of the row, so cache writes and reads follow the fast input price.
    /// nil means the built-in multiplier for the model id being priced; see `PricingTable.price`.
    public var explicitFastMultiplier: Double?

    public init(match: String, input: Double, output: Double, cacheRead: Double? = nil,
                fastMultiplier: Double? = nil) {
        self.match = match
        self.input = input
        self.output = output
        self.explicitCacheRead = cacheRead
        self.explicitFastMultiplier = fastMultiplier
    }

    /// The general cache-read rule: 0.1x input.
    public static let defaultCacheReadRatio = 0.1

    /// Cache write, 5 minute TTL.
    public var cacheWrite5m: Double { input * 1.25 }
    /// Cache write, 1 hour TTL.
    public var cacheWrite1h: Double { input * 2 }
    /// Cache read: the explicit price when the row has one, else 0.1x input.
    public var cacheRead: Double { explicitCacheRead ?? input * ModelPrice.defaultCacheReadRatio }

    /// The same row with every rate multiplied by `factor` (fast mode).
    func scaled(by factor: Double) -> ModelPrice {
        guard factor != 1 else { return self }
        return ModelPrice(match: match, input: input * factor, output: output * factor,
                          cacheRead: explicitCacheRead.map { $0 * factor },
                          fastMultiplier: explicitFastMultiplier)
    }
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
        // Fast mode on Claude Opus 5 is $10 / $50 (2x). Other models' fast-mode rates are not
        // confirmed (Opus 4.8 has fast mode too), so they price fast responses at standard rates.
        ModelPrice(match: "opus-5", input: 5, output: 25, fastMultiplier: 2),
        ModelPrice(match: "opus-4-5", input: 5, output: 25),
        ModelPrice(match: "opus-4-6", input: 5, output: 25),
        ModelPrice(match: "opus-4-7", input: 5, output: 25),
        ModelPrice(match: "opus-4-8", input: 5, output: 25),
        ModelPrice(match: "opus", input: 15, output: 75),
        ModelPrice(match: "sonnet-5", input: 2, output: 10),
        ModelPrice(match: "sonnet", input: 3, output: 15),
        ModelPrice(match: "haiku-4", input: 1, output: 5),
        // Claude 3.5 Haiku's id is `claude-3-5-haiku-<date>` (retired Feb 2026).
        ModelPrice(match: "3-5-haiku", input: 0.8, output: 4),
        ModelPrice(match: "haiku", input: 0.25, output: 1.25),
    ])

    /// The effective price for a model id: the first row whose `match` is a substring of the
    /// lower-cased id (else the fallback), with its cache-read price resolved, and scaled for fast
    /// mode when `fast` is set.
    ///
    /// A row without an explicit `cacheRead` does not simply mean 0.1x input. It means "this row's
    /// input price times the cache-read ratio the built-in table has for this model id" — 0.1 for
    /// every model except Claude Fable 5.1, whose ratio is 0.025. That is what keeps a
    /// `pricing.json` written before amendment A4 (no `cacheRead` field, no `fable-5-1` row, its
    /// generic `fable` row catching Fable 5.1) from pricing Fable 5.1 cache reads 4x too high, while
    /// still honouring whatever input price the user put in that row. A row that gives `cacheRead`
    /// explicitly always wins.
    ///
    /// The fast-mode multiplier follows the same rule (amendment A5): the row's own
    /// `fastMultiplier` when it has one, else the built-in multiplier for this model id (2 for
    /// Claude Opus 5, 1 for everything else), so a `pricing.json` written before A5 still prices
    /// Opus 5 fast responses at twice its own Opus 5 rates.
    public func price(for model: String, fast: Bool = false) -> ModelPrice {
        let m = model.lowercased()
        var p = rows.first { m.contains($0.match) } ?? fallback
        let reference = PricingTable.builtIn.rows.first { m.contains($0.match) } ?? PricingTable.builtIn.fallback
        if p.explicitCacheRead == nil, let referenceRead = reference.explicitCacheRead, reference.input > 0 {
            p.explicitCacheRead = p.input * referenceRead / reference.input
        }
        guard fast else { return p }
        return p.scaled(by: p.explicitFastMultiplier ?? reference.explicitFastMultiplier ?? 1)
    }

    // MARK: - pricing.json

    /// Parse the user-overridable file. Returns nil when the file is missing or unusable, in which
    /// case the caller keeps the built-in table.
    ///
    /// Each row is `{match, input, output}` plus an optional `cacheRead` (USD per million tokens)
    /// and an optional `fastMultiplier`. A `cacheRead` or `fastMultiplier` that is not a finite,
    /// non-negative number is ignored rather than dropping the row, so a typo there cannot re-route
    /// the model to some later, differently priced row; the row then gets the rule described at
    /// `price(for:fast:)`.
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
            var fast: Double?
            if let f = JSONNumber.double(d["fastMultiplier"]), f.isFinite, f >= 0 { fast = f }
            let lower = match.lowercased()
            if lower == "*" || lower == "default" {
                fallback = ModelPrice(match: "*", input: input, output: output, cacheRead: cacheRead, fastMultiplier: fast)
            } else {
                rows.append(ModelPrice(match: lower, input: input, output: output, cacheRead: cacheRead, fastMultiplier: fast))
            }
        }
        guard !rows.isEmpty else { return nil }
        return PricingTable(rows: rows, fallback: fallback)
    }

    public func jsonData() -> Data {
        var s = "{\n  \"_comment\": \"Tokenamp pricing, USD per million tokens. Ordered; the first row whose 'match' is a substring of the lower-cased model id wins. Cache write 5m = 1.25x input, cache write 1h = 2x input. Cache read is the row's 'cacheRead' when given; a row without it uses input x the model's built-in cache-read ratio, which is 0.1 for every model except Claude Fable 5.1 (0.025, i.e. $0.25 at $10 input). Fast-mode responses are priced at the row's rates times its 'fastMultiplier'; a row without it uses the model's built-in multiplier (2 for Claude Opus 5, 1 otherwise). The row matching \\\"*\\\" is the fallback.\",\n  \"models\": [\n"
        var parts: [String] = []
        for r in rows + [ModelPrice(match: "*", input: fallback.input, output: fallback.output,
                                    cacheRead: fallback.explicitCacheRead,
                                    fastMultiplier: fallback.explicitFastMultiplier)] {
            var row = "    { \"match\": \"\(r.match)\", \"input\": \(trim(r.input)), \"output\": \(trim(r.output))"
            if let c = r.explicitCacheRead { row += ", \"cacheRead\": \(trim(c))" }
            if let f = r.explicitFastMultiplier { row += ", \"fastMultiplier\": \(trim(f))" }
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
    private var fastCache: [String: ModelPrice] = [:]

    public init(table: PricingTable = .builtIn) { self.table = table }

    public func setTable(_ t: PricingTable) {
        guard t != table else { return }
        table = t
        cache.removeAll(keepingCapacity: true)
        fastCache.removeAll(keepingCapacity: true)
    }

    public func price(for model: String, fast: Bool = false) -> ModelPrice {
        if fast {
            if let p = fastCache[model] { return p }
            let p = table.price(for: model, fast: true)
            fastCache[model] = p
            return p
        }
        if let p = cache[model] { return p }
        let p = table.price(for: model)
        cache[model] = p
        return p
    }

    /// API-list-price equivalent for one API response. `fast` is `usage.speed == "fast"`.
    public func cost(model: String, input: Int, output: Int, cacheWrite5m: Int, cacheWrite1h: Int, cacheRead: Int,
                     fast: Bool = false) -> Double {
        let p = price(for: model, fast: fast)
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
