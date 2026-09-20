// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only: this module is the Linux platform layer, and SwiftPM
// builds every target in the package on every OS, including a Windows
// `swift test`.
#if os(Linux)

import Foundation
import PlatformKit
#if canImport(Glibc)
import Glibc
#endif

/// inotify-backed folder watcher. Upstream: `DirectoryWatcher` (FSEvents).
/// Watches the directory itself (not recursively) for files created, moved in,
/// written and deleted, and coalesces bursts into one callback per 250 ms.
public final class LinuxFolderWatcher: FolderWatcher, @unchecked Sendable {
    public enum Error: Swift.Error { case inotifyUnavailable, cannotWatch(String) }

    private let lock = NSLock()
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var pending: DispatchWorkItem?

    public init() {}

    public func start(directory: URL, onChange: @escaping @Sendable () -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        stopLocked()
        let fd = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
        guard fd >= 0 else { throw Error.inotifyUnavailable }
        let mask = UInt32(IN_CREATE | IN_MOVED_TO | IN_CLOSE_WRITE | IN_DELETE | IN_MOVED_FROM)
        guard inotify_add_watch(fd, directory.path, mask) >= 0 else {
            close(fd)
            throw Error.cannotWatch(directory.lastPathComponent)
        }
        self.fd = fd
        let queue = DispatchQueue(label: "io.github.nx1x.openmila.folder-watch")
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Drain whatever is queued; the content does not matter, only that
            // something changed.
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while read(fd, &buffer, buffer.count) > 0 {}
            self.scheduleCallback(onChange, on: queue)
        }
        source.resume()
        self.source = source
    }

    private func scheduleCallback(_ onChange: @escaping @Sendable () -> Void, on queue: DispatchQueue) {
        lock.lock(); defer { lock.unlock() }
        pending?.cancel()
        let item = DispatchWorkItem(block: onChange)
        pending = item
        queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: item)
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        pending?.cancel(); pending = nil
        source?.cancel(); source = nil
        if fd >= 0 { close(fd); fd = -1 }
    }

    deinit { stop() }
}
#endif
