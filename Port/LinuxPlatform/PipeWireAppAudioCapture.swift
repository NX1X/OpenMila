// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only.
#if os(Linux)

import AudioCapture
import Foundation
import PlatformKit

/// Capture of ONE application's audio, which is what upstream gets from
/// ScreenCaptureKit: the meeting's other side without the microphone's room,
/// and without the user's music if they have some playing.
///
/// PipeWire can link a capture stream straight to another node's output, and
/// `pw-record --target <serial> --raw` is that link with a process around it.
/// Going through PipeWire's own tool rather than libpipewire is deliberate:
/// the C client would mean a realtime thread, SPA format negotiation and a
/// hard dependency on the library version, for the same result. The cost is a
/// child process per capture and a dependency on `pipewire-bin`, which any
/// system running PipeWire already has.
///
/// The alternative approach - creating a null sink and moving the application
/// to it - is deliberately NOT used: it takes the sound away from the user's
/// speakers while recording.
public struct PipeWireAppAudioCapture: AppAudioCapture {
    private let dump: String
    private let record: String

    public init(dump: String = "pw-dump", record: String = "pw-record") {
        self.dump = dump
        self.record = record
    }

    /// True when PipeWire's tools are on PATH and a graph answers.
    public static var isAvailable: Bool {
        (try? PipeWireAppAudioCapture().applicationStreams()) != nil
    }

    // MARK: AppAudioCapture

    public func targets() throws -> [AudioCaptureTarget] {
        try applicationStreams()
    }

    public func start(target: AudioCaptureTarget) throws -> AudioCaptureSession {
        guard case .application = target.scope else {
            throw AudioCaptureError.deviceUnavailable("That target is not an application stream.")
        }
        return try PipeWireRecordSession(tool: record, targetSerial: target.id)
    }

    // MARK: The graph

    /// Every node PipeWire lists as an application playing audio.
    func applicationStreams() throws -> [AudioCaptureTarget] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [dump]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            throw AudioCaptureError.noBackend("pw-dump could not be run: \(error.localizedDescription)")
        }
        // pw-dump's output is a few hundred kilobytes, which overflows a pipe
        // buffer, so it is read before waiting for the process to exit.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AudioCaptureError.noBackend("pw-dump exited with \(process.terminationStatus).")
        }
        guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw AudioCaptureError.noBackend("pw-dump returned something that is not a graph.")
        }
        return objects.compactMap(Self.target(from:))
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let text = value as? String { return Int(text) }
        return nil
    }

    /// One pw-dump object turned into a target, or nil when it is not an
    /// application playing audio. Internal so a fixture graph can test it
    /// without PipeWire.
    static func target(from object: [String: Any]) -> AudioCaptureTarget? {
        guard let info = object["info"] as? [String: Any],
              let props = info["props"] as? [String: Any],
              props["media.class"] as? String == "Stream/Output/Audio" else { return nil }
        // The serial is what --target takes, and unlike the node id it is
        // never reused within a session, so a target cannot silently become a
        // different application between listing and recording.
        guard let serial = props["object.serial"] else { return nil }
        let application = (props["application.name"] as? String)
            ?? (props["node.name"] as? String)
            ?? "Application"
        let media = props["media.name"] as? String
        // Not every client publishes its pid (pw-play does not); 0 means
        // "unknown", and nothing in the port keys on it - the serial is the
        // handle that matters.
        let pid = Self.integer(props["application.process.id"]).map(Int32.init) ?? 0
        let name = (media == nil || media == application) ? application : "\(application) - \(media!)"
        return AudioCaptureTarget(id: String(describing: serial), name: name,
                                  scope: .application(processID: pid))
    }
}

/// One `pw-record --raw` process, its stdout turned into the same
/// `AsyncStream` of 16 kHz mono frames every other capture backend yields.
final class PipeWireRecordSession: AudioCaptureSession, @unchecked Sendable {
    let samples: AsyncStream<[Float]>
    let backendName = "PipeWire (application)"

    private let continuation: AsyncStream<[Float]>.Continuation
    private let process = Process()
    private let output = Pipe()
    private let lock = NSLock()
    private var frames = 0
    private var stopped = false

    var capturedFrameCount: Int { lock.withLock { frames } }

    init(tool: String, targetSerial: String) throws {
        var continuation: AsyncStream<[Float]>.Continuation!
        // Same policy as the miniaudio session: bound the buffer and drop the
        // oldest audio if the consumer stalls.
        samples = AsyncStream(bufferingPolicy: .bufferingOldest(600)) { continuation = $0 }
        self.continuation = continuation

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            tool, "--target", targetSerial, "--raw",
            "--rate", String(Int(PlatformAudioFormat.sampleRate)),
            "--channels", String(PlatformAudioFormat.channelCount),
            "--format", "f32",
            "--latency", "100ms",
            "-",
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            continuation.finish()
            throw AudioCaptureError.deviceUnavailable("pw-record could not be run: \(error.localizedDescription)")
        }

        // A blocking read gets a thread of its own, never a queue: a pipe that
        // stays open forever must not cost a slot in a shared pool.
        let thread = Thread { [weak self] in self?.pump() }
        thread.name = "io.github.nx1x.openmila.pw-record"
        thread.start()
    }

    private func pump() {
        let handle = output.fileHandleForReading
        var pending = Data()
        while true {
            // The throwing read, not `availableData`: a handle that goes away
            // under a blocked `availableData` traps the whole process instead
            // of returning.
            guard let chunk = try? handle.read(upToCount: 16 * 1024), !chunk.isEmpty else { break }
            pending.append(chunk)
            let whole = pending.count - (pending.count % 4)
            guard whole > 0 else { continue }
            let block = pending.prefix(whole)
            pending.removeFirst(whole)
            // Copied rather than rebound: a Data slice carries no alignment
            // promise, and binding it to Float traps at runtime.
            var values = [Float](repeating: 0, count: whole / 4)
            values.withUnsafeMutableBytes { destination in
                _ = block.copyBytes(to: destination)
            }
            lock.withLock { frames += values.count }
            continuation.yield(values)
        }
        continuation.finish()
    }

    func stop() {
        let alreadyStopped: Bool = lock.withLock {
            let value = stopped
            stopped = true
            return value
        }
        guard !alreadyStopped else { return }
        // Terminating pw-record closes the write end, which ends the pump
        // thread's read. The read end is deliberately NOT closed here: doing
        // that under a blocked read is what takes the process down.
        if process.isRunning { process.terminate() }
        continuation.finish()
    }

    deinit { stop() }
}
#endif
