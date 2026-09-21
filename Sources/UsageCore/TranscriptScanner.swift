import Foundation
import Darwin

/// Everything the scanner knows about one transcript file.
struct ScannedFile {
    var path: String
    var size: UInt64 = 0
    var mtime: Double = 0
    var inode: UInt64 = 0
    /// Bytes consumed; always sits just past a newline, never inside a half-written line.
    var offset: UInt64 = 0
    var events: [UsageEvent] = []
    /// Session this file's events belong to, derived from the path.
    var sessionID: String = ""
}

struct ScanStats {
    var filesConsidered = 0
    var filesParsed = 0
    /// Cumulative for the life of the process.
    var bytesRead: UInt64 = 0
    /// Bytes read by the most recent full scan; this is what the throughput figure divides.
    var lastScanBytes: UInt64 = 0
    var linesPrefiltered = 0
    var linesParsed = 0
    var eventsSeen = 0
    var lastFullScanSeconds: Double = 0
    var lastFullScanAt: Date?
    var loadedFromCache = false
    var cacheLoadSeconds: Double = 0
}

/// Owns all transcript state. Every method must be called from the provider's serial scan queue.
final class TranscriptScanner {

    let root: URL
    /// Files whose mtime is older than this are not scanned at all (SPEC 4.1: 10 days).
    var maxFileAge: TimeInterval = 10 * 86_400
    /// Events older than this are dropped (SPEC 4.1: 11 days).
    var eventTTL: TimeInterval = 11 * 86_400
    /// A file with more unread bytes than this is read after the quick ones on a cold start.
    static var deferredFileBytes: UInt64 = 16 << 20

    private(set) var files: [String: ScannedFile] = [:]
    /// Global dedup index, keyed by `message.id`. See `IndexEntry` for the ownership rule.
    private(set) var byID: [String: IndexEntry] = [:]
    private(set) var stats = ScanStats()

    private var parser = TranscriptLineParser()
    private var sortedCache: [UsageEvent]?
    /// Counted alongside `sortedCache`, for the diagnostics readout.
    private(set) var sharedIDCount = 0
    private(set) var fastEventCount = 0
    /// Bumped whenever the event set changes, so the aggregator knows to rebuild.
    private(set) var generation: UInt64 = 0

    /// Called after every file during a full scan so the owner can publish partial results.
    var onFileProgress: ((Int, Int) -> Void)?

    init(root: URL) {
        // Resolve once, so that the paths the directory enumerator produces and the paths FSEvents
        // reports (which are always fully resolved) are the same strings and hit the same cache
        // entries. `/var/...` vs `/private/var/...` would otherwise be two different files.
        self.root = URL(fileURLWithPath: TokenampPaths.realPath(root.path), isDirectory: true)
    }

    // MARK: - Discovery

    struct Candidate {
        var path: String
        var size: UInt64
        var mtime: Double
        var inode: UInt64
    }

    /// Newest first, so today's numbers appear within a second or two of launch.
    func discover(now: Date) -> [Candidate] {
        var out: [Candidate] = []
        let cutoff = now.timeIntervalSince1970 - maxFileAge
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root,
                                    includingPropertiesForKeys: nil,
                                    options: [.skipsPackageDescendants],
                                    errorHandler: { _, _ in true }) else { return [] }
        for case let url as URL in e {
            guard url.pathExtension == "jsonl" else { continue }
            var st = stat()
            guard stat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
            let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
            guard mtime >= cutoff else { continue }
            out.append(Candidate(path: url.path, size: UInt64(st.st_size), mtime: mtime, inode: UInt64(st.st_ino)))
        }
        out.sort { $0.mtime == $1.mtime ? $0.path < $1.path : $0.mtime > $1.mtime }
        return out
    }

    // MARK: - Scanning

    enum ScanOutcome {
        case unchanged
        case appended
        /// The file shrank or its inode changed: its events were thrown away and re-read, so the
        /// global dedup index has to be rebuilt from scratch.
        case reset
        /// New events arrived, but at least one of them has an id another file also carries, so
        /// the ownership rule has to be re-derived by a rebuild.
        case appendedShared
    }

    /// Full pass: discover, then parse whatever is new in each file, newest first.
    /// `shouldStop` lets the owner abort a cold scan on `stop()`.
    @discardableResult
    func fullScan(now: Date, shouldStop: () -> Bool = { false }) -> Bool {
        let t0 = Date()
        let bytesBefore = stats.bytesRead
        let candidates = discover(now: now)
        stats.filesConsidered = candidates.count
        var changed = false
        var needsRebuild = false
        var done = 0
        let live = Set(candidates.map { $0.path })

        // Forget files that dropped out of the window (or were deleted) so the cache stays bounded.
        let stale = files.keys.filter { !live.contains($0) }
        if !stale.isEmpty {
            for p in stale { files.removeValue(forKey: p) }
            changed = true
            needsRebuild = true
        }

        // Work out what actually has to be read before touching any of it: an untouched file costs
        // one `stat` and nothing else, which is what makes the 30 s safety rescan almost free.
        var pending: [Candidate] = []
        for c in candidates {
            switch prepare(candidate: c) {
            case .unchanged:
                done += 1
            case .reset:
                changed = true
                needsRebuild = true
                pending.append(c)
            case .needsRead:
                pending.append(c)
            }
        }
        onFileProgress?(done, candidates.count)

        // Newest first, but a single multi-hundred-megabyte transcript must not gate the first
        // snapshot: files with a lot of unread bytes go after the quick ones, still newest first.
        // A warm start has nothing unread, so this is a no-op there.
        pending.sort { a, b in
            let heavyA = (a.size - (files[a.path]?.offset ?? 0)) > TranscriptScanner.deferredFileBytes
            let heavyB = (b.size - (files[b.path]?.offset ?? 0)) > TranscriptScanner.deferredFileBytes
            if heavyA != heavyB { return !heavyA }
            if a.mtime != b.mtime { return a.mtime > b.mtime }
            return a.path < b.path
        }

        // Read in batches, several files at a time. The batches start small so that the newest
        // transcripts — today's numbers — land in the first published snapshot, then widen so the
        // rest of the 10 day window overlaps its I/O waits.
        var index = 0
        var batchSize = 1
        while index < pending.count {
            if shouldStop() { break }
            let upper = min(index + batchSize, pending.count)
            let batch = Array(pending[index..<upper])
            index = upper
            batchSize = min(max(batchSize * 4, 4), 32)

            let results = TranscriptScanner.parseInParallel(batch, states: batch.map { files[$0.path] },
                                                           shouldStop: shouldStop)
            for r in results {
                if merge(result: r) { needsRebuild = true }
                if !r.events.isEmpty { changed = true }
            }
            done += batch.count
            onFileProgress?(done, candidates.count)
        }

        // The ownership rule does not depend on read order, and the incremental merge applies it
        // exactly for ids only one file carries. Anything else (a reset file, a vanished file, an
        // id shared between files) is re-derived once here, so a cold scan lands on exactly the
        // same index as a warm start from the cache (which rebuilds by definition).
        if needsRebuild { rebuildIndex() }
        stats.lastScanBytes = stats.bytesRead - bytesBefore
        stats.lastFullScanSeconds = Date().timeIntervalSince(t0)
        stats.lastFullScanAt = Date()
        return changed
    }

    // MARK: - Parallel reading

    enum Preparation {
        case unchanged
        case needsRead
        case reset
    }

    /// Decide what a candidate needs, updating the cheap metadata in place. Called on the scan queue.
    private func prepare(candidate c: Candidate) -> Preparation {
        var state = files[c.path] ?? ScannedFile(path: c.path, sessionID: TranscriptScanner.sessionID(forPath: c.path))
        var wasReset = false
        if state.inode != 0 && (state.inode != c.inode || c.size < state.offset) {
            state.offset = 0
            state.events.removeAll(keepingCapacity: true)
            wasReset = true
        }
        state.mtime = c.mtime
        state.inode = c.inode
        state.size = c.size
        files[c.path] = state
        if state.offset >= c.size { return wasReset ? .reset : .unchanged }
        return wasReset ? .reset : .needsRead
    }

    struct FileParseResult {
        var path: String
        var endOffset: UInt64
        var bytesRead: UInt64
        var prefiltered: Int
        var parsed: Int
        var events: [UsageEvent]
    }

    /// Pure: reads files off the shared state and hands back results to be merged serially.
    ///
    /// `shouldStop` is polled before each file and, inside the reader, once per read window, so
    /// `stop()` during a cold scan waits for at most one window rather than for a whole batch of
    /// very large transcripts. A partially read file keeps its newline-aligned offset and picks up
    /// where it left off next time.
    private static func parseInParallel(_ batch: [Candidate], states: [ScannedFile?],
                                        shouldStop: () -> Bool = { false }) -> [FileParseResult] {
        var results = [FileParseResult?](repeating: nil, count: batch.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: batch.count) { i in
            let c = batch[i]
            let start = states[i]?.offset ?? 0
            if shouldStop() {
                lock.lock()
                results[i] = FileParseResult(path: c.path, endOffset: start, bytesRead: 0,
                                             prefiltered: 0, parsed: 0, events: [])
                lock.unlock()
                return
            }
            let session = states[i]?.sessionID ?? TranscriptScanner.sessionID(forPath: c.path)
            var parser = TranscriptLineParser()
            var events: [UsageEvent] = []
            var prefiltered = 0
            let end = LineReader.forEachLine(path: c.path, from: start, upTo: c.size, shouldStop: shouldStop) { line in
                guard TranscriptLineParser.passesPrefilter(line) else { return }
                prefiltered += 1
                guard let ev = parser.event(from: line, fallbackSession: session) else { return }
                events.append(ev)
            }
            let r = FileParseResult(path: c.path, endOffset: end, bytesRead: end >= start ? end - start : 0,
                                    prefiltered: prefiltered, parsed: parser.parsedLines, events: events)
            lock.lock()
            results[i] = r
            lock.unlock()
        }
        return results.compactMap { $0 }
    }

    /// Fold one file's parse result into the shared state. Scan queue only. Returns true when the
    /// index must be rebuilt to apply the ownership rule.
    private func merge(result r: FileParseResult) -> Bool {
        guard var state = files[r.path] else { return false }
        state.offset = r.endOffset
        if !r.events.isEmpty { state.events.append(contentsOf: r.events) }
        files[r.path] = state

        stats.bytesRead += r.bytesRead
        stats.linesPrefiltered += r.prefiltered
        stats.linesParsed += r.parsed
        stats.eventsSeen += r.events.count
        stats.filesParsed += 1

        return r.events.isEmpty ? false : mergeIntoIndex(r.events, path: r.path)
    }

    /// Incremental tail of a set of paths reported by the watcher.
    @discardableResult
    func tail(paths: [String], now: Date) -> Bool {
        var changed = false
        var needsRebuild = false
        let cutoff = now.timeIntervalSince1970 - maxFileAge
        for path in paths {
            guard path.hasSuffix(".jsonl") else { continue }
            var st = stat()
            guard stat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else {
                if files.removeValue(forKey: path) != nil { changed = true; needsRebuild = true }
                continue
            }
            let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
            guard mtime >= cutoff else { continue }
            let c = Candidate(path: path, size: UInt64(st.st_size), mtime: mtime, inode: UInt64(st.st_ino))
            switch scan(candidate: c) {
            case .unchanged: break
            case .appended: changed = true
            case .reset, .appendedShared: changed = true; needsRebuild = true
            }
        }
        if needsRebuild { rebuildIndex() }
        return changed
    }

    private func scan(candidate c: Candidate) -> ScanOutcome {
        var state = files[c.path] ?? ScannedFile(path: c.path, sessionID: TranscriptScanner.sessionID(forPath: c.path))
        var resetHappened = false

        // Rotation / truncation detection.
        if state.inode != 0 && (state.inode != c.inode || c.size < state.offset) {
            state.offset = 0
            state.events.removeAll(keepingCapacity: true)
            resetHappened = true
        }
        if !resetHappened && state.inode == c.inode && c.size == state.size && state.offset == c.size {
            // Nothing appended since last time, and the last pass consumed every complete line.
            state.mtime = c.mtime
            files[c.path] = state
            return .unchanged
        }
        guard c.size > state.offset else {
            state.size = c.size
            state.mtime = c.mtime
            state.inode = c.inode
            files[c.path] = state
            return resetHappened ? .reset : .unchanged
        }

        let startOffset = state.offset
        var newEvents: [UsageEvent] = []
        var prefiltered = 0
        var parsedCount = 0
        let session = state.sessionID
        let end = LineReader.forEachLine(path: c.path, from: startOffset, upTo: c.size) { line in
            guard TranscriptLineParser.passesPrefilter(line) else { return }
            prefiltered += 1
            guard let ev = parser.event(from: line, fallbackSession: session) else { return }
            parsedCount += 1
            newEvents.append(ev)
        }

        stats.bytesRead += end - startOffset
        stats.linesPrefiltered += prefiltered
        stats.linesParsed += parser.parsedLines
        parser.parsedLines = 0
        stats.eventsSeen += parsedCount
        stats.filesParsed += 1

        state.offset = end
        state.size = c.size
        state.mtime = c.mtime
        state.inode = c.inode
        if !newEvents.isEmpty { state.events.append(contentsOf: newEvents) }
        files[c.path] = state

        if resetHappened { return .reset }
        if newEvents.isEmpty { return .unchanged }
        // Fast path: fold the new events straight into the dedup index.
        return mergeIntoIndex(newEvents, path: c.path) ? .appendedShared : .appended
    }

    // MARK: - Dedup index

    /// Fold newly read events of one file into the index.
    ///
    /// Exact for an id that only this file carries (the common case: a live session appending its
    /// own responses). When an id is also in another file, or this file's sighting of an id that
    /// is shared changes, the entry is updated provisionally and the return value asks the caller
    /// for a rebuild, which re-derives the owner from every file's sighting.
    @discardableResult
    private func mergeIntoIndex(_ events: [UsageEvent], path: String) -> Bool {
        var needsRebuild = false
        for (id, sighting) in TranscriptScanner.sightings(events) {
            if var entry = byID[id] {
                if entry.owner == path {
                    entry.event.mergeWithinFile(sighting)
                    if entry.shared { needsRebuild = true }
                } else {
                    entry.combine(sighting: sighting, path: path)
                    needsRebuild = true
                }
                byID[id] = entry
            } else {
                byID[id] = IndexEntry(event: sighting, owner: path)
            }
        }
        sortedCache = nil
        generation &+= 1
        return needsRebuild
    }

    /// One sighting per id: the lines of one file merged with `mergeWithinFile` (first line's
    /// identity, latest timestamp, maximum counts).
    private static func sightings(_ events: [UsageEvent]) -> [String: UsageEvent] {
        var local = [String: UsageEvent](minimumCapacity: events.count)
        for e in events {
            if var existing = local[e.id] {
                existing.mergeWithinFile(e)
                local[e.id] = existing
            } else {
                local[e.id] = e
            }
        }
        return local
    }

    /// Rebuild the dedup index from scratch. The result does not depend on the order the files are
    /// visited in (see `IndexEntry`), so every path to the same file state gives the same index.
    func rebuildIndex() {
        var index: [String: IndexEntry] = [:]
        index.reserveCapacity(byID.count + 256)
        for f in files.values {
            for (id, sighting) in TranscriptScanner.sightings(f.events) {
                if var existing = index[id] {
                    existing.combine(sighting: sighting, path: f.path)
                    index[id] = existing
                } else {
                    index[id] = IndexEntry(event: sighting, owner: f.path)
                }
            }
        }
        byID = index
        sortedCache = nil
        generation &+= 1
    }

    // MARK: - Eviction

    /// Drop events older than the TTL. Returns true when anything was dropped.
    ///
    /// An event goes as a whole, judged by the timestamp the index gives it (its earliest
    /// sighting), and every line of it leaves every file. Evicting line by line would let a
    /// resumed copy that carries a new timestamp outlive the original line, and the rebuild would
    /// then bring an 11 day old response back as today's usage in the resumed session.
    @discardableResult
    func evict(now: Date) -> Bool {
        let cutoff = now.timeIntervalSince1970 - eventTTL
        var doomed = Set<String>()
        for (id, entry) in byID where entry.event.timestamp < cutoff { doomed.insert(id) }
        guard !doomed.isEmpty else { return false }
        for (path, var f) in files {
            let before = f.events.count
            f.events.removeAll { doomed.contains($0.id) }
            if f.events.count != before { files[path] = f }
        }
        rebuildIndex()
        return true
    }

    // MARK: - Output

    /// Deduped events, oldest first (ties by id, so the order is fully deterministic). Cached until
    /// the event set changes.
    func sortedEvents() -> [UsageEvent] {
        if let c = sortedCache { return c }
        var all: [UsageEvent] = []
        all.reserveCapacity(byID.count)
        var shared = 0
        var fast = 0
        for entry in byID.values {
            all.append(entry.event)
            if entry.shared { shared += 1 }
            if entry.event.fast { fast += 1 }
        }
        all.sort { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp }
        sortedCache = all
        sharedIDCount = shared
        fastEventCount = fast
        return all
    }

    /// Path of the file that owns an id (self-test and diagnostics).
    func owner(of id: String) -> String? { byID[id]?.owner }

    var uniqueEventCount: Int { byID.count }

    // MARK: - Path -> session id

    /// Subagent transcripts live at `<project>/<session-uuid>/subagents/**/agent-*.jsonl` and are
    /// attributed to `<session-uuid>`; a plain transcript is `<project>/<session-uuid>.jsonl`.
    static func sessionID(forPath path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if let i = parts.lastIndex(of: "subagents"), i > 0 {
            return String(parts[i - 1])
        }
        guard let last = parts.last else { return "" }
        var name = String(last)
        if name.hasSuffix(".jsonl") { name.removeLast(6) }
        return name
    }

    // MARK: - Cache

    func loadCache(from url: URL) -> Bool {
        let t0 = Date()
        guard let data = try? Data(contentsOf: url) else { return false }
        guard let loaded = ScanCache.decode(data) else { return false }
        files = loaded
        rebuildIndex()
        stats.loadedFromCache = true
        stats.cacheLoadSeconds = Date().timeIntervalSince(t0)
        return true
    }

    /// Encoding 30 000 events takes long enough to be visible as a stalled clock if it runs on the
    /// scan queue, so the caller gets a value-semantic copy of the state (O(1), copy-on-write) to
    /// encode and write on its own queue.
    func cacheSnapshotForSaving() -> [String: ScannedFile] { files }

    static func writeCache(_ files: [String: ScannedFile], to url: URL) {
        let data = ScanCache.encode(files: files)
        try? TokenampPaths.writeAtomically(data, to: url)
    }
}
