import Foundation
import UsageCore
import UsageModel

// The single seam between the UI half and the data half of Tokenamp.
//
// TokenampKit never depends on UsageCore (see the comment at the top of Package.swift), so the
// executable is the only place the two meet: this file picks which `UsageProvider` the app runs on.

/// Build the provider the app runs on.
/// - Parameter demo: true when `--demo` was passed (or the Demo Data option is on).
func makeProvider(demo: Bool) -> UsageProvider {
    if demo {
        // Deterministic synthetic data: `--demo` and the Demo Data menu item.
        return DemoUsageProvider()
    }
    // Real data: transcripts under ~/.claude/projects plus the account's plan limits.
    // It starts its own queues, timers and FSEvents stream from `start()`; the controller sets
    // `isLiveEnabled`, `livePollInterval` and `isPaused` from the preferences before starting it.
    return LiveUsageProvider()
}

/// True once `makeProvider` hands back real data for a non-demo run. The info panel and the
/// Demo Data menu item read it so the app never shows synthetic numbers as if they were real.
let liveProviderIsWired = true

/// Info-panel lines about the live data layer (clutterbar "I", SPEC 2.1: data sources and paths).
///
/// `LiveUsageProvider` publishes `ScanDiagnostics` on the main thread beside every snapshot for
/// exactly this purpose, but TokenampKit cannot see that type - so the formatting happens here,
/// in the one target that links both halves, and is handed to the UI as plain strings.
func providerDiagnostics(_ provider: UsageProvider) -> [String] {
    guard let live = provider as? LiveUsageProvider else { return [] }
    let d = live.diagnostics
    var lines: [String] = []
    lines.append("  Transcripts:  " + d.transcriptRoot)
    lines.append("  Files:        \(d.filesParsed) read of \(d.filesConsidered) in the 10 day window")
    lines.append(String(format: "  Last pass:    %.2f s, %.0f MB/s", d.lastFullScanSeconds, d.throughputMBPerSecond))
    lines.append(String(format: "  Read:         %.2f GB this run", Double(d.bytesRead) / 1_073_741_824))
    lines.append("  Lines:        \(d.linesParsed) parsed of \(d.linesPrefiltered) past the byte prefilter")
    lines.append("  Events:       \(d.uniqueEvents) unique of \(d.rawEvents) raw")
    lines.append(d.loadedFromCache
                 ? String(format: "  Warm start:   yes, cache loaded in %.3f s", d.cacheLoadSeconds)
                 : "  Warm start:   no - this launch did a cold scan")
    lines.append(String(format: "  Rebuild:      %.1f ms last, %.1f ms worst",
                        d.snapshotBuildSeconds * 1000, d.maxSnapshotBuildSeconds * 1000))
    lines.append("  Cache file:   " + TokenampPaths.scanCacheURL.path)
    lines.append("  Pricing file: " + TokenampPaths.pricingURL.path)
    return lines
}
