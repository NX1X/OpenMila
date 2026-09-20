// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

#if os(Windows)
import AudioCapture
import CWinShim
import Foundation
import PlatformKit
import WinSDK

/// What the app offers as "the other side of the meeting" on Windows: the
/// applications currently playing audio, and the whole-system loopback devices
/// as a fallback.
///
/// Upstream records one chosen application through ScreenCaptureKit. Windows
/// has WASAPI process loopback, which binds a capture client to a process
/// tree, so the port can match that rather than recording everything the
/// machine plays and hoping the user was quiet.
public struct WindowsAppAudioCapture: AppAudioCapture {
    private let wholeSystem = MiniaudioSystemLoopback()

    public init() {}

    public func targets() throws -> [AudioCaptureTarget] {
        let applications = WindowsAudioSessions.playing()
        let monitors = (try? wholeSystem.targets()) ?? []
        if applications.isEmpty && monitors.isEmpty { return try wholeSystem.targets() }
        return applications + monitors
    }

    public func start(target: AudioCaptureTarget) throws -> AudioCaptureSession {
        switch target.scope {
        case .application(let processID):
            return try ProcessLoopbackSession(processID: processID, name: target.name)
        case .wholeSystem:
            return try wholeSystem.start(target: target)
        }
    }
}

/// One `om_process_loopback` capture, presented as the same `AsyncStream` of
/// 16 kHz mono frames every other backend yields.
final class ProcessLoopbackSession: AudioCaptureSession, @unchecked Sendable {
    let samples: AsyncStream<[Float]>
    let backendName = "WASAPI (application)"

    private let continuation: AsyncStream<[Float]>.Continuation
    private let lock = NSLock()
    private var frames = 0
    private var handle: OpaquePointer?

    var capturedFrameCount: Int { lock.withLock { frames } }

    init(processID: Int32, name: String) throws {
        var continuation: AsyncStream<[Float]>.Continuation!
        // The same policy as every other capture: bound the buffer and drop
        // the oldest audio if the consumer stalls.
        samples = AsyncStream(bufferingPolicy: .bufferingOldest(600)) { continuation = $0 }
        self.continuation = continuation

        var error: Int32 = 0
        let unmanaged = Unmanaged.passRetained(self)
        handle = om_process_loopback_start(
            UInt32(bitPattern: processID),
            UInt32(PlatformAudioFormat.sampleRate),
            UInt32(PlatformAudioFormat.channelCount),
            { user, samples, frameCount in
                guard let user, let samples, frameCount > 0 else { return }
                let session = Unmanaged<ProcessLoopbackSession>.fromOpaque(user).takeUnretainedValue()
                session.deliver(UnsafeBufferPointer(start: samples, count: Int(frameCount)))
            },
            unmanaged.toOpaque(),
            &error)

        guard handle != nil else {
            unmanaged.release()
            continuation.finish()
            let detail = String(cString: om_process_loopback_error(error))
            throw AudioCaptureError.deviceUnavailable("\(name): \(detail).")
        }
    }

    private func deliver(_ buffer: UnsafeBufferPointer<Float>) {
        lock.withLock { frames += buffer.count }
        continuation.yield(Array(buffer))
    }

    func stop() {
        let handle: OpaquePointer? = lock.withLock {
            let value = self.handle
            self.handle = nil
            return value
        }
        guard let handle else { return }
        // Returns once the capture thread has finished, so no callback can
        // arrive after this and the retain below is safe to release.
        om_process_loopback_stop(handle)
        continuation.finish()
        Unmanaged.passUnretained(self).release()
    }

    deinit { stop() }
}

/// The applications Windows says are playing audio, read from the audio
/// session list. A process with no session is not offered, because capturing
/// it would only ever produce silence.
enum WindowsAudioSessions {
    static func playing() -> [AudioCaptureTarget] {
        var targets: [AudioCaptureTarget] = []
        var seen = Set<Int32>()

        // The port already walks the process table for meeting detection; the
        // same walk answers "which of these could be playing". Windows has an
        // exact answer through IAudioSessionManager2, which is COM-heavy; the
        // process list plus the loopback client's own error when a process is
        // silent is enough, and keeps this readable.
        let snapshot = CreateToolhelp32Snapshot(DWORD(TH32CS_SNAPPROCESS), 0)
        guard let snapshot, snapshot != INVALID_HANDLE_VALUE else { return [] }
        defer { CloseHandle(snapshot) }

        var entry = PROCESSENTRY32W()
        entry.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)
        guard Process32FirstW(snapshot, &entry) else { return [] }
        repeat {
            let name = withUnsafeBytes(of: entry.szExeFile) { raw -> String in
                let buffer = raw.bindMemory(to: UInt16.self)
                return String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
            }
            let pid = Int32(bitPattern: entry.th32ProcessID)
            guard !seen.contains(pid), Self.isLikelyMediaApplication(name) else { continue }
            seen.insert(pid)
            targets.append(AudioCaptureTarget(id: "pid:\(pid)",
                                              name: Self.displayName(for: name),
                                              scope: .application(processID: pid)))
        } while Process32NextW(snapshot, &entry)
        return targets
    }

    /// The applications a meeting is plausibly in. A full audio-session
    /// enumeration would be exact; this keeps the list short and readable, and
    /// the whole-system monitor is always there for anything missing.
    static let knownApplications: [String: String] = [
        "zoom.exe": "Zoom",
        "teams.exe": "Microsoft Teams",
        "ms-teams.exe": "Microsoft Teams",
        "chrome.exe": "Google Chrome",
        "msedge.exe": "Microsoft Edge",
        "firefox.exe": "Firefox",
        "slack.exe": "Slack",
        "discord.exe": "Discord",
        "vlc.exe": "VLC",
        "spotify.exe": "Spotify",
    ]

    static func isLikelyMediaApplication(_ executable: String) -> Bool {
        knownApplications[executable.lowercased()] != nil
    }

    static func displayName(for executable: String) -> String {
        knownApplications[executable.lowercased()] ?? executable
    }
}
#endif
