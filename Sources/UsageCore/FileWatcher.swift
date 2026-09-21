import Foundation
import CoreServices

/// File-level FSEvents watch over the transcript root.
///
/// File-level events (rather than directory-level) mean the handler is told exactly which
/// transcript grew, so the scanner tails that one file instead of re-walking the tree.
final class FileWatcher {

    private var stream: FSEventStreamRef?
    private let queue: DispatchQueue
    private let handler: ([String]) -> Void
    private let path: String
    private let latency: CFTimeInterval
    /// `start`/`stop` may be reached from the scan queue and from `deinit` on any thread.
    private let lock = NSLock()

    init(path: String, latency: CFTimeInterval = 0.3, queue: DispatchQueue, handler: @escaping ([String]) -> Void) {
        self.path = path
        self.latency = latency
        self.queue = queue
        self.handler = handler
    }

    deinit { stop() }

    @discardableResult
    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil else { return true }
        // The stream must own a strong reference to the watcher: it calls back on `queue`, and
        // without these the callback would read a `FileWatcher` that the last release had already
        // freed. FSEvents calls `retain` once when the stream is created and `release` once when
        // the stream is released, so passing the pointer unretained keeps the count balanced.
        let retainInfo: CFAllocatorRetainCallBack = { info in
            guard let info else { return nil }
            return UnsafeRawPointer(Unmanaged<FileWatcher>.fromOpaque(info).retain().toOpaque())
        }
        let releaseInfo: CFAllocatorReleaseCallBack = { info in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).release()
        }
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: retainInfo, release: releaseInfo, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagWatchRoot)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info, count > 0 else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let array = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            watcher.handler(array)
        }
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, callback, &context,
                                          [path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          latency, flags) else { return false }
        FSEventStreamSetDispatchQueue(s, queue)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            return false
        }
        stream = s
        return true
    }

    func stop() {
        lock.lock()
        let s = stream
        stream = nil
        lock.unlock()
        guard let s else { return }
        FSEventStreamStop(s)
        // Unscheduling from the dispatch queue is the documented way to be sure no further
        // callback runs; after this returns the handler can no longer fire.
        FSEventStreamSetDispatchQueue(s, nil)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
    }
}
