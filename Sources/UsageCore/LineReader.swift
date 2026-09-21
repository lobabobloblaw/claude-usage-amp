import Foundation
import Darwin

/// Reads complete `\n`-terminated lines out of a file in windows, with `pread(2)` into one buffer
/// that is reused for the whole file.
///
/// Why windows and not `String(contentsOf:)`: the transcript tree is 3.4 GB inside the 10 day
/// window and single lines reach several megabytes, so the file is never materialised as a String
/// and only one window is resident at a time. A trailing line that has no newline yet is
/// **never** handed to the caller and never counted as consumed, so a half-written line is picked
/// up on the next pass once Claude Code finishes it.
///
/// Why `pread` and not `mmap` (which this used to be): a mapping is only as good as the file under
/// it. The caller's size comes from a `stat` taken earlier, and a transcript can be truncated or
/// rewritten after that — or while a window is being walked. Touching a mapped page that now lies
/// past end of file raises SIGBUS and kills the whole app, and no check made beforehand can close
/// that window. `pread` just returns fewer bytes. The copy it adds costs nothing measurable: a real
/// 4.2 GB cold scan (no scan cache, page cache warm, release build) ran at ~3,870 MB/s against
/// mmap's ~3,810 MB/s, seven alternating runs each.
///
/// On a file that shrinks, the reader stops at the last newline inside the bytes it actually got
/// and returns that offset. It never reports a byte past the real end of file as consumed, so the
/// scanner's own rule (`size < offset` means the file was truncated: drop its events and re-read
/// it from zero) sees the truncation on its next pass, which the truncation's FSEvent triggers.
enum LineReader {

    /// Default read window. Grown temporarily when a single line is bigger than it.
    static let defaultWindow = 4 << 20
    /// Hard ceiling on the growth. A line this big can never be a usage event (the parser's own
    /// cap is far lower), so instead of growing without bound the reader skips the window and
    /// resynchronises at the next newline.
    static let maxWindow = 64 << 20

    /// Reads `count` bytes at `offset` into `buffer`, or as many as the file still has. Returns
    /// the number of bytes read; fewer than `count` means end of file (the file is shorter than
    /// the caller thought) or an I/O error, and the reader treats both as "the file ends here".
    typealias ReadAt = (_ buffer: UnsafeMutableRawPointer, _ count: Int, _ offset: UInt64) -> Int

    /// Calls `body` for each complete line in `path` starting at `from`, and returns the offset
    /// just past the last newline consumed. `body` must not escape the buffer.
    /// `shouldStop` is polled once per read window so that quitting during a cold scan does not
    /// have to wait for a 200 MB transcript to be read to the end. The returned offset is a
    /// newline boundary (except just after an abandoned over-long line, see `maxWindow`), so an
    /// aborted read simply resumes there next time. `fileSize` is only an upper bound: the size of
    /// the open descriptor is checked again, and bytes appended after it are left for the next pass.
    @discardableResult
    static func forEachLine(path: String,
                            from start: UInt64,
                            upTo fileSize: UInt64,
                            window: Int = defaultWindow,
                            maxWindow: Int = maxWindow,
                            shouldStop: () -> Bool = { false },
                            _ body: (UnsafeRawBufferPointer) -> Void) -> UInt64 {
        guard start < fileSize else { return start }
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return start }
        defer { close(fd) }
        // The caller stat'd the path earlier; the file may have shrunk since.
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size >= 0 else { return start }
        let end = min(fileSize, UInt64(st.st_size))
        return forEachLine(from: start, upTo: end, window: window, maxWindow: maxWindow,
                           shouldStop: shouldStop,
                           readAt: { buffer, count, offset in preadFully(fd, buffer, count, offset) },
                           body)
    }

    /// The loop itself, over any positioned read. Split out so the self-test can drive it with a
    /// read function that shrinks the "file" at an exact point in the middle of a pass.
    static func forEachLine(from start: UInt64,
                            upTo end: UInt64,
                            window: Int = defaultWindow,
                            maxWindow: Int = maxWindow,
                            shouldStop: () -> Bool = { false },
                            readAt: ReadAt,
                            _ body: (UnsafeRawBufferPointer) -> Void) -> UInt64 {
        guard start < end, window > 0 else { return start }
        // Never allocate a 4 MB window for a 2 KB file (most transcripts are small).
        var capacity = Int(min(UInt64(window), end - start))
        guard var buffer = malloc(capacity) else { return start }
        defer { free(buffer) }

        var pos = start
        var windowSize = window

        while pos < end {
            if shouldStop() { break }
            let want = Int(min(UInt64(windowSize), end - pos))
            if want > capacity {
                guard let grown = realloc(buffer, want) else { break }
                buffer = grown
                capacity = want
            }
            let got = min(max(readAt(buffer, want, pos), 0), want)
            if got == 0 { break }                       // the file now ends at or before `pos`

            var consumed = 0
            var lineStart = 0
            while lineStart < got {
                guard let nl = memchr(buffer.advanced(by: lineStart), 0x0A, got - lineStart) else { break }
                let idx = UnsafeRawPointer(nl) - UnsafeRawPointer(buffer)
                let lineLength = idx - lineStart
                if lineLength > 0 {
                    body(UnsafeRawBufferPointer(start: buffer.advanced(by: lineStart), count: lineLength))
                }
                lineStart = idx + 1
                consumed = lineStart
            }

            let shortRead = got < want                  // the file shrank while being read
            if consumed == 0 {
                // No newline anywhere in this window.
                if shortRead || pos + UInt64(got) >= end { break }   // partial trailing line: leave it
                if windowSize >= maxWindow {
                    // Absurdly long single line: give up on it, skip the window and pick the file
                    // back up at the next newline rather than growing the buffer without bound.
                    pos += UInt64(got)
                    continue
                }
                windowSize = min(windowSize * 2, maxWindow)          // one very long line: widen
                continue
            }
            pos += UInt64(consumed)
            windowSize = window
            if shortRead { break }      // whatever follows the last newline is the new end of file
        }
        return pos
    }

    /// `pread` until `count` bytes are in, end of file, or an error. Retries `EINTR`.
    static func preadFully(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int, _ offset: UInt64) -> Int {
        var done = 0
        while done < count {
            let n = pread(fd, buffer.advanced(by: done), count - done, off_t(offset) + off_t(done))
            if n > 0 { done += n; continue }
            if n < 0 && errno == EINTR { continue }
            break
        }
        return done
    }
}

/// Byte-level helpers used by the prefilter.
enum ByteSearch {
    @inline(__always)
    static func contains(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        guard let hay = haystack.baseAddress, haystack.count >= needle.count else { return false }
        return needle.withUnsafeBytes { n in
            memmem(hay, haystack.count, n.baseAddress!, n.count) != nil
        }
    }
}
