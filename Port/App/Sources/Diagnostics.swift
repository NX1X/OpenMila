// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `Mila/Actions/DiagnosticReporter.swift` (which is AppKit-bound:
// save panel, `log show`, `ditto`). Same content, same redaction rule: every
// settings namespace is included, credentials are redacted and prompts are
// reported as lengths; recording titles and paths never appear.

import Foundation
import OpenMilaLogging
@testable import Mila

enum Diagnostics {
    @MainActor
    static func buildReport(model: AppModel) async throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let root = model.platform.paths.cacheDirectory.appendingPathComponent("diagnostics", isDirectory: true)
        let payload = root.appendingPathComponent("OpenMila-DiagnosticReport-\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)

        let info = ProcessInfo.processInfo
        let system = """
        app=\(AppIdentity.name) \(AppIdentity.version) (Mila \(AppIdentity.upstreamVersion))
        os=\(info.operatingSystemVersionString)
        arch=\(OpenMilaLog.architecture) cores=\(info.activeProcessorCount) ram_gb=\(info.physicalMemory / 1_073_741_824)
        session=\(info.environment["XDG_SESSION_TYPE"] ?? "?") desktop=\(info.environment["XDG_CURRENT_DESKTOP"] ?? "?")
        whisper_backend=CPU
        generated=\(stamp)
        """
        try system.write(to: payload.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)

        // Recordings: shape only, never titles or file names.
        let rows = model.store.recordings.map { r in
            "\(r.id) created=\(ISO8601DateFormatter().string(from: r.createdAt)) duration=\(Int(r.duration)) source=\(r.source.rawValue) status=\(r.status.rawValue) lang=\(r.language) segments=\(r.segments.count) speakers=\(Set(r.segments.compactMap(\.speaker)).count) trashed=\(r.deletedAt != nil)"
        }
        try (["count=\(rows.count) folders=\(model.store.folders.count)"] + rows).joined(separator: "\n")
            .write(to: payload.appendingPathComponent("recordings.txt"), atomically: true, encoding: .utf8)

        let settings = UserDefaults.standard.dictionaryRepresentation()
            .filter { key, _ in key.contains(".") && !key.hasPrefix("NS") && !key.hasPrefix("Apple") }
            .map { key, value -> String in
                let lower = key.lowercased()
                if lower.contains("key") || lower.contains("token") || lower.contains("secret") || lower.contains("password") {
                    return "\(key)=<redacted>"
                }
                if lower.contains("prompt"), let text = value as? String { return "\(key)=<\(text.count) chars>" }
                if lower.contains("bookmark") || lower.contains("path") || lower.contains("directory") { return "\(key)=<path>" }
                return "\(key)=\(value)"
            }
            .sorted()
        try settings.joined(separator: "\n").write(to: payload.appendingPathComponent("settings.txt"), atomically: true, encoding: .utf8)

        let logs = payload.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: model.platform.paths.logDirectory.path)) ?? [] {
            try? FileManager.default.copyItem(at: model.platform.paths.logDirectory.appendingPathComponent(name),
                                              to: logs.appendingPathComponent(name))
        }

        let zipURL = root.appendingPathComponent(payload.lastPathComponent + ".zip")
        try? FileManager.default.removeItem(at: zipURL)
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = root
        zip.arguments = ["-qr", zipURL.path, payload.lastPathComponent]
        zip.standardOutput = FileHandle.nullDevice
        zip.standardError = FileHandle.nullDevice
        if FileManager.default.isExecutableFile(atPath: zip.executableURL!.path) {
            try zip.run()
            zip.waitUntilExit()
            if zip.terminationStatus == 0 {
                try? FileManager.default.removeItem(at: payload)
                return zipURL
            }
        }
        return payload
    }
}
