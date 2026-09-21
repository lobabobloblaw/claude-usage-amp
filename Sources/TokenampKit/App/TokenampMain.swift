import AppKit
import Foundation
import UsageModel

/// The executable's whole body, so `Sources/Tokenamp/main.swift` stays a two-liner and the
/// snapshot / selftest paths never touch `NSApplication`.
public enum TokenampMain {

    /// - Parameters:
    ///   - providerFactory: `makeProvider(demo:)` from the executable target.
    ///   - liveProviderAvailable: false while the executable still returns demo data for a live run.
    ///   - providerDiagnostics: optional info-panel lines about the provider, formatted by the
    ///     executable because only it can see the data layer's own types.
    public static func run(arguments argv: [String],
                           providerFactory: @escaping (Bool) -> UsageProvider,
                           liveProviderAvailable: Bool,
                           providerDiagnostics: ((UsageProvider) -> [String])? = nil) -> Int32 {
        let args = Arguments(Array(argv.dropFirst()))

        if args.help {
            print(Arguments.usage)
            return 0
        }

        if args.selftest {
            return SelfTest.run() ? 0 : 1
        }

        if let dir = args.snapshotDirectory {
            return runSnapshot(args: args, directory: dir, providerFactory: providerFactory)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(arguments: args, providerFactory: providerFactory,
                                   liveProviderAvailable: liveProviderAvailable,
                                   providerDiagnostics: providerDiagnostics)
        app.delegate = delegate
        app.run()
        return 0
    }

    // MARK: - --snapshot

    private static func runSnapshot(args: Arguments, directory: String,
                                    providerFactory: (Bool) -> UsageProvider) -> Int32 {
        let loaded = SkinCatalog.load(args.skinPath ?? SkinCatalog.defaultSkinName)
        let skin = loaded.skin
        if let err = loaded.error { FileHandle.standardError.write(Data(("warning: " + err + "\n").utf8)) }

        let snapshot: UsageSnapshot
        let now: Date
        if args.demo {
            now = args.demoClock
            snapshot = DemoUsageProvider(frozenAt: now).snapshot
        } else {
            // Live: wait up to 8 s for the first real data, then render whatever we have.
            let provider = providerFactory(false)
            provider.start()
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline, !snapshotIsReady(provider.snapshot) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            snapshot = provider.snapshot
            provider.stop()
            now = Date()
        }

        if !args.demo, !snapshotIsReady(snapshot) {
            FileHandle.standardError.write(Data("warning: rendering before the data layer was ready (live: \(snapshot.liveStatus), scanning: \(snapshot.localStatus.isScanning))\n".utf8))
        }

        do {
            let result = try SnapshotRunner.run(directory: directory, skin: skin, snapshot: snapshot,
                                                scale: args.resolvedScale, stateName: args.state, now: now)
            print("skin: \(result.skinName)")
            for w in result.warnings { print("  warning: \(w)") }
            for f in result.files { print("wrote \(f.path)") }
            return 0
        } catch {
            FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
            return 1
        }
    }

    /// SPEC 3.1: a live `--snapshot` "waits up to 8 s for the first live **and** local data".
    ///
    /// The obvious test - "are the arrays non-empty?" - is useless against the real provider, which
    /// hands out correctly shaped all-zero arrays from its initialiser precisely so the UI never has
    /// to guard against short ones. Waiting for real content instead means asking two questions:
    /// has the live source reported anything at all (any state but `.neverFetched`), and has the
    /// local scan actually produced a result (an event, or a completed scan that found nothing)?
    static func snapshotIsReady(_ s: UsageSnapshot) -> Bool {
        let liveSettled: Bool
        switch s.liveStatus {
        case .neverFetched: liveSettled = false
        default: liveSettled = true
        }
        let localSettled = s.lastEventAt != nil || (!s.localStatus.isScanning && s.localStatus.filesTotal > 0)
        return liveSettled && localSettled
    }
}
