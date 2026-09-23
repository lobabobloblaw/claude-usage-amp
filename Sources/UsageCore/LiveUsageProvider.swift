import Foundation
import UsageModel

/// What the CLI (and the app's info panel) can report about the data layer's own behaviour.
public struct ScanDiagnostics: Sendable, Equatable {
    public var filesConsidered = 0
    public var filesParsed = 0
    public var bytesRead: UInt64 = 0
    public var lastScanBytes: UInt64 = 0
    public var linesPrefiltered = 0
    public var linesParsed = 0
    public var rawEvents = 0
    public var uniqueEvents = 0
    public var lastFullScanSeconds: Double = 0
    public var loadedFromCache = false
    public var cacheLoadSeconds: Double = 0
    public var firstScanComplete = false
    public var livePollAttempted = false
    public var snapshotBuildSeconds: Double = 0
    /// Worst snapshot rebuild seen in this run — the number that matters for UI smoothness.
    public var maxSnapshotBuildSeconds: Double = 0
    public var transcriptRoot = ""
    /// Unique events that more than one transcript carries (resumed or forked sessions).
    public var sharedEvents = 0
    /// Unique events served in fast mode (`usage.speed == "fast"`).
    public var fastEvents = 0

    public var throughputMBPerSecond: Double {
        guard lastFullScanSeconds > 0 else { return 0 }
        return Double(lastScanBytes) / 1_048_576 / lastFullScanSeconds
    }
}

/// The real data layer: transcripts on disk + the account's plan limits, published as immutable
/// `UsageSnapshot` values on the main thread.
///
/// Threading (SPEC 4 / `UsageProvider`): `scanQueue` is a serial queue that owns **all** mutable
/// scan state — the scanner, the aggregator, the limit gauges and the poll schedule. Snapshots are
/// built there and handed to the main thread as values. Nothing does file I/O on the main thread.
public final class LiveUsageProvider: UsageProvider {

    // MARK: - Main-thread facing

    public private(set) var snapshot: UsageSnapshot
    public private(set) var diagnostics = ScanDiagnostics()
    public var onChange: ((UsageSnapshot) -> Void)?

    public var isPaused: Bool = false {
        didSet {
            guard oldValue != isPaused else { return }
            let v = isPaused
            scanQueue.async { [weak self] in
                guard let self else { return }
                self.paused = v
                guard !v, self.running else { return }
                // File changes that arrived while paused were dropped, so resuming has to look at
                // the tree again rather than wait up to 30 s for the safety rescan.
                self.runFullScan(progressive: false)
                self.checkLivePoll(force: false)
                self.publish(force: true)
            }
        }
    }

    public var isLiveEnabled: Bool = true {
        didSet {
            guard oldValue != isLiveEnabled else { return }
            let v = isLiveEnabled
            scanQueue.async { [weak self] in
                guard let self else { return }
                self.liveEnabled = v
                if v {
                    self.checkLivePoll(force: true)
                } else {
                    self.limits = []
                    self.planName = ""
                    self.liveStatus = .disabled
                    self.resetPollAt = nil
                }
                // Without this the cached aggregate would be reused and the gauges would linger.
                self.limitsStamp += 1
                self.publish(force: true)
            }
        }
    }

    public var livePollInterval: TimeInterval = 60 {
        didSet {
            let v = min(900, max(30, livePollInterval))
            // Clamp the stored value too, so reading the property back tells the truth about what
            // the provider will actually do (a menu that ticks the current interval depends on it).
            // Assigning inside `didSet` does not re-enter the observer.
            if v != livePollInterval { livePollInterval = v }
            scanQueue.async { [weak self] in self?.pollInterval = v }
        }
    }

    // MARK: - Queues

    private let scanQueue = DispatchQueue(label: "app.tokenamp.scan", qos: .utility)
    private let watchQueue = DispatchQueue(label: "app.tokenamp.watch", qos: .utility)
    /// Cache writing only; never touches live scan state, only value-semantic copies of it.
    ///
    /// `.utility`, not `.background`: background is the discretionary band and is I/O-throttled, so
    /// on a loaded machine a queued cache write can sit there for many seconds — which `stop()`
    /// then has to wait out before the process may exit.
    private let ioQueue = DispatchQueue(label: "app.tokenamp.cache", qos: .utility)

    // MARK: - scanQueue-owned state

    private let scanner: TranscriptScanner
    private let pricing = PricingResolver()
    private let aggregator: Aggregator
    private let limitsClient = LimitsClient()
    /// Self-test seam: replaces the network fetch. nil means `limitsClient`.
    private let fetchOverride: ((@escaping (LiveFetchOutcome) -> Void) -> Void)?
    private var watcher: FileWatcher?
    private var ticker: DispatchSourceTimer?

    /// Main-thread flag guarding `start()` / `stop()`; `running` is the scan queue's own copy.
    private var started = false
    /// Read from inside the scan loop so a cold scan aborts quickly on `stop()`.
    private let controlLock = NSLock()
    private var stopRequested = false
    private var running = false
    private var paused = false
    private var liveEnabled = true
    private var pollInterval: TimeInterval = 60

    private var limits: [LimitGauge] = []
    private var planName = ""
    private var liveStatus: LiveStatus = .neverFetched
    private var localStatus = LocalStatus()

    private var lastPublishAt = Date.distantPast
    private var lastPollAt = Date.distantPast
    private var nextAllowedPollAt = Date.distantPast
    private var pollBackoff: TimeInterval = 0
    private var pollInFlight = false
    /// Set when a limit's reset time passes: poll soon after it for the new window's reading.
    private var resetPollAt: Date?
    /// Minimum gap between polls, and the delay from a reset to the poll after it. Fixed at init;
    /// only the self-test shortens them.
    private let minPollSpacing: TimeInterval
    private let resetPollDelay: () -> TimeInterval
    private var lastEventEpoch: Double = 0
    /// Hand-off slot for a live result that arrived while the scan queue was busy scanning.
    private let liveLock = NSLock()
    private var pendingOutcome: LiveFetchOutcome?

    /// The scanner's `persistGeneration` at the last cache write; the cache is dirty exactly when
    /// this no longer matches. Not the event-set `generation`: an offset that moves past lines with
    /// no usage in them must be saved too, or every launch re-reads those bytes.
    private var lastSavedGeneration: UInt64 = .max
    private var lastCacheSaveAt = Date.distantPast
    private var tickCount = 0
    private var firstScanComplete = false
    private var maxSnapshotBuild: Double = 0
    private var livePollAttempted = false

    // Reuse of the previous aggregate when neither the data nor the 5 s grid moved.
    private var cachedSnapshot: UsageSnapshot?
    private var cachedGeneration: UInt64 = .max
    private var cachedFineIndex: Double = -1
    private var cachedLimitsStamp = -1

    private var limitsStamp = 0
    private let cacheURL: URL
    private let pricingURL: URL

    // MARK: - Init

    /// Testing / self-test entry point: everything relocatable.
    public convenience init(root: URL = TokenampPaths.transcriptsRoot,
                            cacheURL: URL = TokenampPaths.scanCacheURL,
                            pricingURL: URL = TokenampPaths.pricingURL) {
        self.init(root: root, cacheURL: cacheURL, pricingURL: pricingURL, fetch: nil)
    }

    /// Self-test entry point: `fetch` stands in for the network (nil means the real
    /// `LimitsClient`), and the poll spacing and post-reset delay can be shortened.
    init(root: URL, cacheURL: URL, pricingURL: URL,
         fetch: ((@escaping (LiveFetchOutcome) -> Void) -> Void)?,
         minPollSpacing: TimeInterval = LivePollPolicy.minSpacing,
         resetPollDelay: @escaping () -> TimeInterval = { LivePollPolicy.resetPollDelay() }) {
        fetchOverride = fetch
        self.minPollSpacing = minPollSpacing
        self.resetPollDelay = resetPollDelay
        scanner = TranscriptScanner(root: root)
        aggregator = Aggregator(pricing: pricing)
        self.cacheURL = cacheURL
        self.pricingURL = pricingURL
        snapshot = UsageSnapshot.empty()
        diagnostics.transcriptRoot = root.path
        // Hand the UI correctly shaped (all-zero) arrays before any I/O has happened.
        snapshot = aggregator.snapshot(events: [], now: Date(), planName: "", limits: [],
                                       liveStatus: .neverFetched, localStatus: LocalStatus())
    }

    // MARK: - UsageProvider

    public func start() {
        guard !started else { return }
        started = true
        controlLock.lock()
        stopRequested = false
        controlLock.unlock()
        let live = isLiveEnabled
        let interval = min(900, max(30, livePollInterval))
        let pausedNow = isPaused
        scanQueue.async { [weak self] in
            guard let self else { return }
            self.running = true
            self.liveEnabled = live
            self.pollInterval = interval
            self.paused = pausedNow
            self.bootstrap()
        }
    }

    /// Stops scanning and flushes the scan cache **before returning**, so a process that exits on
    /// the next line still gets a warm start next time. A cold scan in flight is asked to abort
    /// through `stopRequested` first — the readers check it once per read window — and the wait
    /// for the cache write is capped at `flushTimeout`, so quitting can never hang the main thread.
    public func stop() {
        guard started else { return }
        started = false
        controlLock.lock()
        stopRequested = true
        controlLock.unlock()
        scanQueue.sync {
            self.running = false
            self.watcher?.stop()
            self.watcher = nil
            self.ticker?.cancel()
            self.ticker = nil
            self.flushCacheNow()
        }
    }

    public func refreshNow() {
        // Main thread per the `UsageProvider` contract, so this is ordered before the block below:
        // resuming is part of what the Play button means (SPEC 2.1).
        if isPaused { isPaused = false }
        scanQueue.async { [weak self] in
            guard let self, self.running else { return }
            self.paused = false
            self.checkLivePoll(force: true)
            self.runFullScan(progressive: true)
            self.publish(force: true)
        }
    }

    // MARK: - Boot

    private func bootstrap() {
        pricing.setTable(PricingTable.loadOrCreateDefault(at: pricingURL))

        // 1. Warm start from the cache: a full snapshot before a single transcript byte is read.
        if scanner.loadCache(from: cacheURL) {
            scanner.evict(now: Date())
            // `diagnostics` belongs to the main thread; publish() copies the numbers across.
            publish(force: true)
        }

        // 2. Live limits, immediately.
        checkLivePoll(force: true)

        // 3. Watch, then scan newest-first while publishing as results accumulate.
        startWatching()
        startTicker()
        runFullScan(progressive: true)
        // A cold scan reads whole files, so it picks up events older than the event TTL from files
        // that are themselves inside the 10 day file window. Evicting here means a cold start and a
        // warm start hold exactly the same event set (and the cache written below is already
        // pruned), instead of differing until the first 30 s tick.
        scanner.evict(now: Date())
        firstScanComplete = true
        saveCacheIfNeeded(force: true)
        publish(force: true)
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let w = FileWatcher(path: scanner.root.path, latency: 0.3, queue: watchQueue) { [weak self] paths in
            guard let self else { return }
            let interesting = paths.filter { $0.hasSuffix(".jsonl") }
            guard !interesting.isEmpty else { return }
            self.scanQueue.async {
                guard self.running, !self.paused else { return }
                if self.scanner.tail(paths: interesting, now: Date()) {
                    self.publish(force: true)
                }
            }
        }
        if w.start() { watcher = w }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: scanQueue)
        t.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        ticker = t
    }

    // MARK: - Tick

    private func tick() {
        guard running else { return }
        tickCount += 1
        if paused { return }
        // Safety rescan every 30 s, in case FSEvents missed something.
        if tickCount % 30 == 0 {
            runFullScan(progressive: false)
            scanner.evict(now: Date())
        }
        // Every 5 s for the normal cadence; every second while a post-reset poll is due, so the
        // new window's reading arrives a few seconds after the reset rather than up to 5 s later.
        if tickCount % 5 == 0 || (resetPollAt.map { Date() >= $0 } ?? false) { checkLivePoll(force: false) }
        if tickCount % 10 == 0 { saveCacheIfNeeded(force: false) }
        publish(force: false)
    }

    // MARK: - Scanning

    /// `progressive` drives the "SCANNING n/m" readout and publishes partial results. The 30 s
    /// safety rescan passes false, because it normally reads nothing and must not make the UI
    /// flicker into a scanning state twice a minute.
    private func runFullScan(progressive: Bool) {
        if progressive {
            localStatus = LocalStatus(isScanning: true, filesDone: 0, filesTotal: localStatus.filesTotal)
            scanner.onFileProgress = { [weak self] done, total in
                guard let self else { return }
                self.localStatus = LocalStatus(isScanning: true, filesDone: done, filesTotal: total)
                // The ticker cannot run while the scan owns the queue, so the things it would
                // have done are driven from here instead.
                self.drainLiveOutcome()
                self.publish(force: false, minimumInterval: 0.15)
                self.saveCacheIfNeeded(force: false)
            }
        }
        let changed = scanner.fullScan(now: Date(), shouldStop: { [weak self] in self?.shouldAbort ?? true })
        scanner.onFileProgress = nil
        let total = scanner.stats.filesConsidered
        localStatus = LocalStatus(isScanning: false, filesDone: total, filesTotal: total)
        _ = changed
        publish(force: true)
    }

    private var shouldAbort: Bool {
        controlLock.lock()
        defer { controlLock.unlock() }
        return stopRequested
    }

    /// Debounced, off-queue cache write. The state is handed over as a value (copy-on-write, so the
    /// copy itself is free) and encoded on `ioQueue`, because encoding tens of thousands of events
    /// on the scan queue would show up as a stalled clock in the UI.
    private func saveCacheIfNeeded(force: Bool) {
        guard scanner.persistGeneration != lastSavedGeneration else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastCacheSaveAt) >= 10 else { return }
        lastCacheSaveAt = now
        lastSavedGeneration = scanner.persistGeneration
        let copy = scanner.cacheSnapshotForSaving()
        let url = cacheURL
        ioQueue.async { TranscriptScanner.writeCache(copy, to: url) }
    }

    /// Longest `stop()` will wait for the scan cache to reach the disk. Quitting must never be
    /// held up by a slow or wedged filesystem; losing the warm start costs one cold scan.
    static let flushTimeout: TimeInterval = 5

    /// Synchronous flush used by `stop()`.
    ///
    /// `stop()` is called on the main thread and reaches here through `scanQueue.sync`, which GCD
    /// may run on the calling thread — so the write itself is pushed onto `ioQueue` with `async`
    /// and waited for. That keeps the promise that no file I/O ever executes on the main thread,
    /// while still guaranteeing the cache is on disk before `stop()` returns. The wait is bounded:
    /// a warm start is a nicety, a frozen Quit is not.
    private func flushCacheNow() {
        if scanner.persistGeneration != lastSavedGeneration {
            lastSavedGeneration = scanner.persistGeneration
            lastCacheSaveAt = Date()
            let copy = scanner.cacheSnapshotForSaving()
            let url = cacheURL
            // Someone is waiting on this one, so it is not a background chore any more.
            ioQueue.async(qos: .userInitiated, flags: .enforceQoS) { TranscriptScanner.writeCache(copy, to: url) }
        }
        // Drain the io queue: everything queued above, plus anything the debounced path left.
        // The barrier is raised to the same priority so it cannot be starved behind it either.
        let done = DispatchSemaphore(value: 0)
        ioQueue.async(qos: .userInitiated, flags: .enforceQoS) { done.signal() }
        _ = done.wait(timeout: .now() + LiveUsageProvider.flushTimeout)
    }

    // MARK: - Live limits

    private func checkLivePoll(force: Bool) {
        guard liveEnabled, !paused, !pollInFlight else { return }
        let now = Date()
        var rateLimited = false
        if case .rateLimited = liveStatus { rateLimited = true }
        let recentLocalActivity = lastEventEpoch > 0 && (now.timeIntervalSince1970 - lastEventEpoch) <= 300
        // A 429 is the service telling us to wait. "Refresh Now" overrides our own backoff, but
        // not an explicit instruction from the server — ignoring it only earns a longer ban. The
        // post-reset poll waits for both (SPEC 4.3).
        guard LivePollPolicy.shouldPoll(force: force, now: now, lastPollAt: lastPollAt,
                                        nextAllowedAt: nextAllowedPollAt, rateLimited: rateLimited,
                                        recentActivity: recentLocalActivity, interval: pollInterval,
                                        resetPollAt: resetPollAt, minSpacing: minPollSpacing) else { return }
        pollInFlight = true
        livePollAttempted = true
        // Any poll that starts after a reset fetches the new window, so it satisfies the pending one.
        resetPollAt = nil
        let deliver: (LiveFetchOutcome) -> Void = { [weak self] outcome in
            guard let self else { return }
            // Park the result where the scan loop can pick it up too: a cold scan owns the scan
            // queue for as long as it runs, and the gauges should not have to wait for it.
            self.liveLock.lock()
            self.pendingOutcome = outcome
            self.liveLock.unlock()
            self.scanQueue.async { self.drainLiveOutcome() }
        }
        if let fetchOverride { fetchOverride(deliver) } else { limitsClient.fetch(completion: deliver) }
    }

    /// Scan queue only.
    private func drainLiveOutcome() {
        liveLock.lock()
        let outcome = pendingOutcome
        pendingOutcome = nil
        liveLock.unlock()
        guard let outcome else { return }
        handle(outcome)
    }

    private func handle(_ outcome: LiveFetchOutcome) {
        pollInFlight = false
        lastPollAt = Date()
        let schedule = LivePollPolicy.schedule(outcome: outcome, now: lastPollAt, previousBackoff: pollBackoff)
        nextAllowedPollAt = schedule.nextAllowedAt
        pollBackoff = schedule.backoff
        switch outcome {
        case .success(let plan, let gauges):
            planName = plan
            // A reading whose reset time has already passed (the service had not rolled over yet)
            // is shown as the new, empty window straight away. No extra poll is scheduled for it:
            // one just happened, and the normal cadence fetches the real reading.
            limits = LimitRollover.roll(gauges, now: lastPollAt).gauges
            liveStatus = .ok(lastFetch: lastPollAt)
        case .authExpired:
            liveStatus = .authExpired
            limits = []
        case .rateLimited:
            // The gauges already on screen are the last true reading; keep showing them.
            liveStatus = .rateLimited(retryAt: nextAllowedPollAt)
        case .failure(let message):
            liveStatus = .error(message)
        }
        limitsStamp += 1
        publish(force: true)
    }

    // MARK: - Publishing

    private func publish(force: Bool, minimumInterval: TimeInterval = 0) {
        // A live poll can land after `stop()` (the request is already in flight). Publishing then
        // would call `onChange` on a provider the UI has stopped, and would overwrite the snapshot
        // it is holding.
        guard running else { return }
        let now = Date()
        if !force && minimumInterval > 0 && now.timeIntervalSince(lastPublishAt) < minimumInterval { return }
        lastPublishAt = now

        let t0 = Date()
        let snap = buildSnapshot(now: now)
        let build = Date().timeIntervalSince(t0)
        if build > maxSnapshotBuild { maxSnapshotBuild = build }

        var diag = ScanDiagnostics()
        diag.filesConsidered = scanner.stats.filesConsidered
        diag.filesParsed = scanner.stats.filesParsed
        diag.bytesRead = scanner.stats.bytesRead
        diag.lastScanBytes = scanner.stats.lastScanBytes
        diag.linesPrefiltered = scanner.stats.linesPrefiltered
        diag.linesParsed = scanner.stats.linesParsed
        diag.rawEvents = scanner.stats.eventsSeen
        diag.uniqueEvents = scanner.uniqueEventCount
        diag.lastFullScanSeconds = scanner.stats.lastFullScanSeconds
        diag.loadedFromCache = scanner.stats.loadedFromCache
        diag.cacheLoadSeconds = scanner.stats.cacheLoadSeconds
        diag.firstScanComplete = firstScanComplete
        diag.livePollAttempted = livePollAttempted && !pollInFlight
        diag.snapshotBuildSeconds = build
        diag.maxSnapshotBuildSeconds = maxSnapshotBuild
        diag.transcriptRoot = scanner.root.path
        diag.sharedEvents = scanner.sharedIDCount
        diag.fastEvents = scanner.fastEventCount

        lastEventEpoch = snap.lastEventAt?.timeIntervalSince1970 ?? lastEventEpoch

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // `started` is the main thread's own flag and `stop()` clears it first, so a snapshot
            // that was already in flight when the UI stopped the provider is dropped here rather
            // than delivered to a controller that has torn itself down.
            guard self.started else { return }
            self.snapshot = snap
            self.diagnostics = diag
            self.onChange?(snap)
        }
    }

    /// A limit whose reset time has passed is republished as the new window (0 %, next reset), and
    /// a poll is scheduled a few seconds later for the service's own reading. Without this the
    /// gauge would sit at its pre-reset value with the countdown stuck at 00:00 until the next
    /// poll — minutes normally, indefinitely offline.
    private func rollLimitsIfNeeded(now: Date) {
        guard !limits.isEmpty else { return }
        let r = LimitRollover.roll(limits, now: now)
        guard r.rolled else { return }
        limits = r.gauges
        limitsStamp += 1
        let due = now.addingTimeInterval(resetPollDelay())
        resetPollAt = min(resetPollAt ?? .distantFuture, due)
    }

    private func buildSnapshot(now: Date) -> UsageSnapshot {
        if liveEnabled { rollLimitsIfNeeded(now: now) }
        let fineIndex = (now.timeIntervalSince1970 / UsageSnapshot.fineBucketSeconds).rounded(.down)
        if let cached = cachedSnapshot,
           cachedGeneration == scanner.generation,
           cachedFineIndex == fineIndex,
           cachedLimitsStamp == limitsStamp {
            // Nothing moved: hand back the same aggregate with a fresh timestamp. This is what
            // keeps idle CPU at essentially zero while still publishing once a second.
            var s = cached
            s.generatedAt = now
            s.localStatus = localStatus
            return s
        }
        let snap = aggregator.snapshot(events: scanner.sortedEvents(),
                                       now: now,
                                       planName: liveEnabled ? planName : "",
                                       limits: liveEnabled ? limits : [],
                                       liveStatus: liveEnabled ? liveStatus : .disabled,
                                       localStatus: localStatus)
        cachedSnapshot = snap
        cachedGeneration = scanner.generation
        cachedFineIndex = fineIndex
        cachedLimitsStamp = limitsStamp
        return snap
    }
}
