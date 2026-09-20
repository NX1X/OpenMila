// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `Mila/VoiceMemos/DirectoryWatcher.swift` (FSEvents). Same
// contract: watch one directory, coalesce bursts by `latency`, call
// `onChange` on a background queue.
//
// inotify on Linux. On Windows this polls instead: the kernel call that would
// do it properly (ReadDirectoryChangesW) lives in the platform layer, which the
// core cannot reach without inverting the dependency, and the only caller is
// the watched-folder importer, where a second of latency costs nothing.

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
    #if os(Windows)
    private var timer: DispatchSourceTimer?
    private var lastSeen: [String: Date] = [:]
    #endif

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
        #elseif os(Windows)
        guard timer == nil else { return }
        lastSeen = Self.snapshot(of: path)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = max(1.0, latency)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Self.snapshot(of: self.path)
            guard now != self.lastSeen else { return }
            self.lastSeen = now
            self.onChange()
        }
        timer.resume()
        self.timer = timer
        #endif
    }

    #if os(Windows)
    /// Each entry's modification date, which changes when a file is added,
    /// removed, renamed or written.
    private static func snapshot(of path: String) -> [String: Date] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: path) else { return [:] }
        var result: [String: Date] = [:]
        for name in names {
            let attributes = try? manager.attributesOfItem(atPath: path + "\\" + name)
            result[name] = (attributes?[.modificationDate] as? Date) ?? .distantPast
        }
        return result
    }
    #endif

    func stop() {
        pending?.cancel(); pending = nil
        source?.cancel(); source = nil
        #if os(Windows)
        timer?.cancel(); timer = nil
        #else
        if fd >= 0 { close(fd); fd = -1 }
        #endif
    }

    deinit { stop() }
}
