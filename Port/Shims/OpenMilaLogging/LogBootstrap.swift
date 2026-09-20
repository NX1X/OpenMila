// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Where OpenMila's logs go. macOS Mila logs to the unified log and lets
// `log show` collect it; off macOS the app keeps its own files so a user can
// send them in with a bug report.
//
// Layout: <log directory>/openmila.log, rotated at 2 MB into openmila.1.log ..
// openmila.5.log. Every line: ISO-8601 time, level, subsystem/category,
// message. `.private` interpolations are redacted before they get here
// (see Logger.swift), so a log file never carries user content unless the
// user ran with OPENMILA_LOG_PRIVATE=1 on purpose.

import Foundation
import Logging

public enum OpenMilaLog {
    /// Default log directory: `$XDG_STATE_HOME/openmila/logs` (Linux, falling
    /// back to `~/.local/state`), `%LOCALAPPDATA%\OpenMila\logs` (Windows).
    public static var defaultDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        #if os(Windows)
        let base = env["LOCALAPPDATA"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AppData/Local")
        return base.appendingPathComponent("OpenMila/logs", isDirectory: true)
        #else
        let base = env["XDG_STATE_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
        return base.appendingPathComponent("openmila/logs", isDirectory: true)
        #endif
    }

    public static var currentFile: URL { defaultDirectory.appendingPathComponent("openmila.log") }

    private static let lock = NSLock()
    private static var installed = false

    /// Route every `Logger` in the process to stderr and the rotating file.
    /// Safe to call more than once; only the first call takes effect.
    /// `OPENMILA_LOG_LEVEL` (trace, debug, info, notice, warning, error) sets
    /// the threshold; the default is `info`.
    public static func install(processName: String, version: String,
                               directory: URL? = nil, alsoStderr: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true

        let directory = directory ?? defaultDirectory
        let level = Self.level(from: ProcessInfo.processInfo.environment["OPENMILA_LOG_LEVEL"])
        let file = RotatingFileSink(directory: directory, baseName: "openmila", maxBytes: 2_000_000, keep: 5)

        LoggingSystem.bootstrap { label in
            var handlers: [LogHandler] = [FileLogHandler(label: label, sink: file)]
            if alsoStderr { handlers.append(StreamLogHandler.standardError(label: label)) }
            var handler = MultiplexLogHandler(handlers)
            handler.logLevel = level
            return handler
        }

        // One header per launch so a log a user sends says what it came from.
        let info = ProcessInfo.processInfo
        var header = Logging.Logger(label: "io.github.nx1x.openmila")
        header.logLevel = .trace
        header.notice("""
            \(processName) \(version) starting: \
            os=\(info.operatingSystemVersionString) \
            arch=\(Self.architecture) \
            cores=\(info.activeProcessorCount) \
            ram=\(info.physicalMemory / 1_073_741_824)GB \
            locale=\(Locale.current.identifier) \
            log_level=\(level) \
            private_logging=\(OpenMilaLogPrivacy.revealPrivate) \
            log_file=\(directory.appendingPathComponent("openmila.log").path)
            """)
    }

    static func level(from text: String?) -> Logging.Logger.Level {
        switch text?.lowercased() {
        case "trace": return .trace
        case "debug": return .debug
        case "notice": return .notice
        case "warning", "warn": return .warning
        case "error": return .error
        case "critical": return .critical
        default: return .info
        }
    }

    public static var architecture: String {
        #if arch(x86_64)
        return "x86_64"
        #elseif arch(arm64)
        return "arm64"
        #else
        return "unknown"
        #endif
    }
}

/// Appends lines to a file and rotates it when it grows past `maxBytes`.
final class RotatingFileSink: @unchecked Sendable {
    private let directory: URL
    private let baseName: String
    private let maxBytes: Int
    private let keep: Int
    private let lock = NSLock()
    private var handle: FileHandle?
    private var written = 0

    init(directory: URL, baseName: String, maxBytes: Int, keep: Int) {
        self.directory = directory
        self.baseName = baseName
        self.maxBytes = maxBytes
        self.keep = keep
    }

    private var currentURL: URL { directory.appendingPathComponent("\(baseName).log") }

    func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if handle == nil { open() }
        guard let handle else { return }
        let data = Data((line + "\n").utf8)
        do {
            try handle.write(contentsOf: data)
        } catch {
            return
        }
        written += data.count
        if written >= maxBytes { rotate() }
    }

    private func open() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: currentURL.path) {
                _ = fm.createFile(atPath: currentURL.path, contents: nil,
                                  attributes: [.posixPermissions: 0o600])
            }
            let h = try FileHandle(forWritingTo: currentURL)
            written = Int((try? h.seekToEnd()) ?? 0)
            handle = h
        } catch {
            handle = nil
        }
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        let oldest = directory.appendingPathComponent("\(baseName).\(keep).log")
        try? fm.removeItem(at: oldest)
        for index in stride(from: keep - 1, through: 1, by: -1) {
            let from = directory.appendingPathComponent("\(baseName).\(index).log")
            let to = directory.appendingPathComponent("\(baseName).\(index + 1).log")
            if fm.fileExists(atPath: from.path) { try? fm.moveItem(at: from, to: to) }
        }
        try? fm.moveItem(at: currentURL, to: directory.appendingPathComponent("\(baseName).1.log"))
        written = 0
        open()
    }
}

struct FileLogHandler: LogHandler {
    let label: String
    let sink: RotatingFileSink
    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .info

    private static let timestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(level: Logging.Logger.Level, message: Logging.Logger.Message,
             metadata: Logging.Logger.Metadata?, source: String,
             file: String, function: String, line: UInt) {
        let merged = self.metadata.merging(metadata ?? [:]) { $1 }
        let category = merged["category"].map { "/\($0)" } ?? ""
        sink.write("\(Self.timestamp.string(from: Date())) \(level) \(label)\(category) \(message)")
    }
}
