// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `Mila/VoiceMemos/DirectoryWatcher.swift` (FSEvents). Same
// contract: watch one directory, coalesce bursts by `latency`, call
// `onChange` on a background queue. inotify on Linux; Windows follows.

import Foundation
#if canImport(Glibc)
import Glibc
#endif

final class DirectoryWatcher {
    private let path: String
    private let latency: TimeInterval
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "io.github.nx1x.openmila.directory-watcher")
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var pending: DispatchWorkItem?

    init(path: String, latency: TimeInterval = 1.0, onChange: @escaping () -> Void) {
        self.path = path
        self.latency = latency
        self.onChange = onChange
    }

    func start() {
        #if os(Linux)
        guard source == nil else { return }
        let fd = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
        guard fd >= 0 else { return }
        let mask = UInt32(IN_CREATE | IN_MOVED_TO | IN_CLOSE_WRITE | IN_DELETE | IN_MOVED_FROM | IN_ONLYDIR)
        guard inotify_add_watch(fd, path, mask) >= 0 else { close(fd); return }
        self.fd = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while read(fd, &buffer, buffer.count) > 0 {}
            self.pending?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.onChange() }
            self.pending = item
            self.queue.asyncAfter(deadline: .now() + self.latency, execute: item)
        }
        source.resume()
        self.source = source
        #endif
    }

    func stop() {
        pending?.cancel(); pending = nil
        source?.cancel(); source = nil
        if fd >= 0 { close(fd); fd = -1 }
    }

    deinit { stop() }
}
