import Foundation
import Darwin

/// Reads complete `\n`-terminated lines out of a file by mapping it in windows.
///
/// Why mapping and not `String(contentsOf:)`: the transcript tree is 3.4 GB inside the 10 day
/// window and single lines reach several megabytes, so the file is never materialised as a String
/// and only whole windows are resident at a time. A trailing line that has no newline yet is
/// **never** handed to the caller and never counted as consumed, so a half-written line is picked
/// up on the next pass once Claude Code finishes it.
enum LineReader {

    /// Default mapping window. Grown temporarily when a single line is bigger than it.
    static let defaultWindow = 4 << 20
    /// Hard ceiling on the growth. A line this big can never be a usage event (the parser's own
    /// cap is far lower), so instead of growing without bound the reader skips the window and
    /// resynchronises at the next newline.
    static let maxWindow = 64 << 20

    /// Calls `body` for each complete line in `path` starting at `from`, and returns the offset
    /// just past the last newline consumed. `body` must not escape the buffer.
    /// `shouldStop` is polled once per mapping window so that quitting during a cold scan does not
    /// have to wait for a 200 MB transcript to be read to the end. The returned offset is always a
    /// newline boundary, so an aborted read simply resumes there next time.
    @discardableResult
    static func forEachLine(path: String,
                            from start: UInt64,
                            upTo fileSize: UInt64,
                            window: Int = defaultWindow,
                            maxWindow: Int = maxWindow,
                            shouldStop: () -> Bool = { false },
                            _ body: (UnsafeRawBufferPointer) -> Void) -> UInt64 {
        guard start < fileSize else { return start }
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return start }
        defer { close(fd) }

        let pageSize = UInt64(getpagesize())
        var pos = start
        var windowSize = window

        while pos < fileSize {
            if shouldStop() { break }
            let mapStart = (pos / pageSize) * pageSize
            let lead = Int(pos - mapStart)
            let length = Int(min(UInt64(windowSize) + UInt64(lead), fileSize - mapStart))
            guard length > 0 else { break }
            guard let base = mmap(nil, length, PROT_READ, MAP_PRIVATE, fd, off_t(mapStart)),
                  base != MAP_FAILED else { break }
            madvise(base, length, MADV_SEQUENTIAL)

            var consumed = lead
            var lineStart = lead
            while lineStart < length {
                let remaining = length - lineStart
                guard let nl = memchr(base.advanced(by: lineStart), 0x0A, remaining) else { break }
                let idx = UnsafeRawPointer(nl) - UnsafeRawPointer(base)
                let lineLength = idx - lineStart
                if lineLength > 0 {
                    body(UnsafeRawBufferPointer(start: base.advanced(by: lineStart), count: lineLength))
                }
                lineStart = idx + 1
                consumed = lineStart
            }

            madvise(base, length, MADV_DONTNEED)
            munmap(base, length)

            if consumed == lead {
                // No newline anywhere in this window.
                if mapStart + UInt64(length) >= fileSize { break }   // partial trailing line: leave it
                if windowSize >= maxWindow {
                    // Absurdly long single line: give up on it, skip the window and pick the file
                    // back up at the next newline rather than growing the mapping without bound.
                    pos = mapStart + UInt64(length)
                    continue
                }
                windowSize = min(windowSize * 2, maxWindow)          // one very long line: widen
                continue
            }
            pos = mapStart + UInt64(consumed)
            windowSize = window
        }
        return pos
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
