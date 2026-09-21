// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `Mila/Audio/AudioCompressor.swift` (AVFoundation AAC on macOS).
//
// Same two entry points. Off macOS the codec work is delegated to an `ffmpeg`
// executable, found on PATH, because neither Linux nor SwiftPM ships an AAC
// encoder. Two upstream features depend on it: compact `.m4a` recordings, and
// the remote transcription backend, which uploads AAC to stay under API size
// limits. When ffmpeg is missing both fail with a message that says so.
//
// Subprocess handling follows `.claude/rules/python-subprocess.md`: output goes
// to the null device, so there is no pipe to fill and deadlock on, and the wait
// is bounded.

import Foundation
import OSLog

private let compressorLog = Logger(subsystem: "io.github.nx1x.openmila", category: "AudioCompressor")

enum AudioCompressor {
    enum CompressError: Error, LocalizedError, Equatable {
        case makeBuffer
        case encoderUnavailable
        case encoderFailed(status: Int32)
        case encoderTimedOut

        var errorDescription: String? {
            switch self {
            case .makeBuffer:
                return "Could not allocate an audio buffer."
            case .encoderUnavailable:
                return "Audio conversion needs ffmpeg or GStreamer, and neither was found. Install ffmpeg and try again."
            case .encoderFailed(let status):
                return "Audio conversion failed (ffmpeg exited with status \(status))."
            case .encoderTimedOut:
                return "Audio conversion timed out."
            }
        }
    }

    /// Overridable so tests can point at a stub or simulate a missing encoder.
    static var encoderOverride: URL??

    static func compress(wavURL: URL, toM4A destURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.removeItem(at: destURL)
            }
            if locateEncoder() == nil, let pipeline = locateGStreamer() {
                try runGStreamer(pipeline, [
                    "filesrc", "location=\(wavURL.path)", "!", "wavparse", "!", "audioconvert", "!",
                    "audioresample", "!", "avenc_aac", "bitrate=32000", "!", "mp4mux", "!",
                    "filesink", "location=\(destURL.path)",
                ])
                compressorLog.log("compressed with GStreamer (no ffmpeg on this machine)")
                return
            }
            try runEncoder([
                "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", wavURL.path,
                "-vn", "-c:a", "aac", "-b:a", "32k",
                "-f", "ipod", destURL.path,
            ])
            // Both names are title-derived; keep them out of public log fields.
            compressorLog.log("""
                compressed \(wavURL.lastPathComponent, privacy: .private) -> \
                \(destURL.lastPathComponent, privacy: .private)
                """)
        }.value
    }

    static func decodeToTempWAV(_ url: URL) throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmila-decode-\(UUID().uuidString).wav")
        do {
            if locateEncoder() == nil, let pipeline = locateGStreamer() {
                try runGStreamer(pipeline, [
                    "filesrc", "location=\(url.path)", "!", "decodebin", "!", "audioconvert", "!",
                    "audioresample", "!",
                    "audio/x-raw,format=F32LE,channels=1,rate=16000", "!", "wavenc", "!",
                    "filesink", "location=\(temp.path)",
                ])
                return temp
            }
            try runEncoder([
                "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", url.path,
                "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_f32le",
                "-f", "wav", temp.path,
            ])
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        return temp
    }

    // MARK: - GStreamer, the second route

    /// `gst-launch-1.0`, which a GNOME or KDE install almost always has even
    /// where ffmpeg does not, so AAC recordings and imported files work on a
    /// machine that never installed ffmpeg. ffmpeg stays the first choice: one
    /// command, no pipeline to get wrong.
    static func locateGStreamer() -> URL? {
        if let gstreamerOverride { return gstreamerOverride }
        #if os(Windows)
        let name = "gst-launch-1.0.exe"
        let separator: Character = ";"
        #else
        let name = "gst-launch-1.0"
        let separator: Character = ":"
        #endif
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: separator) where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Overridable for the same reason as `encoderOverride`.
    static var gstreamerOverride: URL??

    private static func runGStreamer(_ tool: URL, _ arguments: [String], timeout: TimeInterval = 600) throws {
        try run(tool, ["-q"] + arguments, timeout: timeout)
    }

    // MARK: - ffmpeg

    static func locateEncoder() -> URL? {
        if let encoderOverride { return encoderOverride }
        #if os(Windows)
        let names = ["ffmpeg.exe"]
        let separator: Character = ";"
        #else
        let names = ["ffmpeg"]
        let separator: Character = ":"
        #endif
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: separator) where !directory.isEmpty {
            for name in names {
                let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    private static func runEncoder(_ arguments: [String], timeout: TimeInterval = 600) throws {
        guard let encoder = locateEncoder() else {
            // Only now is it truly unavailable: the GStreamer route is tried
            // before this is called.
            throw CompressError.encoderUnavailable
        }
        try run(encoder, arguments, timeout: timeout)
    }

    private static func run(_ tool: URL, _ arguments: [String], timeout: TimeInterval) throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 5)
            throw CompressError.encoderTimedOut
        }
        guard process.terminationStatus == 0 else {
            throw CompressError.encoderFailed(status: process.terminationStatus)
        }
    }
}
