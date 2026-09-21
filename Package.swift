// swift-tools-version:5.9
import PackageDescription

// Target graph (keep it acyclic and keep the two big targets independent of each other):
//
//   UsageModel   – plain value types + UsageProvider protocol + DemoUsageProvider. No I/O.
//   UsageCore    – real data: transcript scanner, live plan-limit client, pricing. Depends on UsageModel only.
//   usage-dump   – CLI for exercising UsageCore without any UI.
//   TokenampKit  – skin engine, windows, rendering. Depends on UsageModel only (never on UsageCore).
//   Tokenamp     – the app executable; the only place where UsageCore and TokenampKit meet.
//
// No SwiftPM resources are used anywhere (Bundle.module breaks inside a hand-assembled .app);
// runtime resources are located through TokenampKit's ResourceLocator.
let package = Package(
    name: "Tokenamp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Tokenamp", targets: ["Tokenamp"]),
        .executable(name: "usage-dump", targets: ["usage-dump"]),
    ],
    targets: [
        .target(name: "UsageModel", path: "Sources/UsageModel"),
        .target(name: "UsageCore", dependencies: ["UsageModel"], path: "Sources/UsageCore"),
        .executableTarget(name: "usage-dump", dependencies: ["UsageCore", "UsageModel"], path: "Sources/usage-dump"),
        .target(name: "TokenampKit", dependencies: ["UsageModel"], path: "Sources/TokenampKit"),
        // INTEGRATION (done): both halves are finished, so the executable now links UsageCore and
        // Sources/Tokenamp/ProviderFactory.swift hands the UI a LiveUsageProvider for a non-demo run.
        // This is still the ONLY target that depends on both UsageCore and TokenampKit.
        .executableTarget(name: "Tokenamp", dependencies: ["TokenampKit", "UsageModel", "UsageCore"], path: "Sources/Tokenamp"),
    ],
    swiftLanguageVersions: [.v5]
)
