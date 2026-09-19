// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `Mila/Audio/RecordingSession.swift`. The mixing rules are
// upstream's, kept line for line where they are pure arithmetic:
//   - the microphone is the master clock;
//   - app audio is parked in a jitter buffer and mixed against each mic chunk,
//     averaged where both legs overlap and full scale where only one exists;
//   - the buffer is capped at 30 s and an overflow is flushed to the file,
//     not dropped;
//   - a pause discards everything that arrives, so the paused span is absent
//     from both the file and the live feed;
//   - stop flushes the buffered tail at full scale.
// What differs is the plumbing: capture arrives as `[Float]` chunks from a
// `PlatformKit` session instead of `AVAudioPCMBuffer`s, and the file is a
// `WAVFileWriter` instead of `AVAudioFile`.

import Foundation
import PlatformKit

public enum CaptureSource: String, Sendable {
    case microphone, systemAudio, meeting
}

public enum RecordingState: Equatable, Sendable {
    case idle, recording, paused, stopping
}

/// The mixing arithmetic on its own, so it is testable without a device.
public struct MeetingMixer: Sendable {
    /// ~30 s at 16 kHz, upstream's cap on the parked app audio.
    public static let maxPending = Int(PlatformAudioFormat.sampleRate) * 30

    public private(set) var pendingSystem: [Float] = []
    public private(set) var overflowFlushes = 0

    public init() {}

    /// Park app audio for the mic clock. Returns any overflow that must be
    /// written out immediately (the mic clock has stalled).
    public mutating func park(system samples: [Float]) -> [Float] {
        pendingSystem.append(contentsOf: samples)
        guard pendingSystem.count > Self.maxPending else { return [] }
        let overflowCount = pendingSystem.count - Self.maxPending
        let overflow = Array(pendingSystem.prefix(overflowCount))
        pendingSystem.removeFirst(overflowCount)
        overflowFlushes += 1
        return overflow
    }

    /// Mix one mic chunk with the head of the parked app audio.
    public mutating func mix(mic: [Float]) -> [Float] {
        let n = mic.count
        let take = min(n, pendingSystem.count)
        var mixed = [Float](repeating: 0, count: n)
        for i in 0..<n {
            mixed[i] = i < take ? (mic[i] + pendingSystem[i]) * 0.5 : mic[i]
        }
        if take > 0 { pendingSystem.removeFirst(take) }
        return mixed
    }

    public mutating func drainTail() -> [Float] {
        let tail = pendingSystem
        pendingSystem.removeAll(keepingCapacity: false)
        return tail
    }

    public mutating func discardPending() {
        pendingSystem.removeAll(keepingCapacity: false)
    }
}

@MainActor
public final class RecordingSession {
    public private(set) var state: RecordingState = .idle
    public private(set) var source: CaptureSource = .microphone
    public private(set) var fileURL: URL?
    public private(set) var captureEpoch = 0
    /// Mic frames captured by the most recent recording, read after `stop()`
    /// to tell a dead input from a normal one.
    public private(set) var lastMicFrameCount = 0

    /// Live meters, in dBFS-free 0...1 RMS like upstream's `RecordingMeters`.
    public private(set) var micLevel: Float = 0
    public private(set) var systemLevel: Float = 0
    public var elapsed: TimeInterval {
        guard let startTime else { return 0 }
        let now = pausedAt ?? Date()
        return max(0, now.timeIntervalSince(startTime) - totalPaused)
    }

    /// Post-mix chunks for the live transcriber.
    public var onLiveSamples: (([Float]) -> Void)?

    private let microphone: MicrophoneCapture
    private let appAudio: AppAudioCapture?
    private var micSession: AudioCaptureSession?
    private var systemSession: AudioCaptureSession?
    private var micTask: Task<Void, Never>?
    private var systemTask: Task<Void, Never>?
    private var writer: WAVFileWriter?
    private var mixer = MeetingMixer()
    private var startTime: Date?
    private var pausedAt: Date?
    private var totalPaused: TimeInterval = 0

    public init(microphone: MicrophoneCapture, appAudio: AppAudioCapture?) {
        self.microphone = microphone
        self.appAudio = appAudio
    }

    public func start(source: CaptureSource, outputURL: URL,
                      micDeviceID: String? = nil, appTarget: AudioCaptureTarget? = nil) throws {
        guard state == .idle else { return }
        self.source = source
        mixer = MeetingMixer()
        do {
            writer = try WAVFileWriter(url: outputURL)
            fileURL = outputURL
            if source == .microphone || source == .meeting {
                let session = try microphone.start(deviceID: micDeviceID)
                micSession = session
                micTask = Task { [weak self] in
                    for await chunk in session.samples { await self?.consumeMic(chunk) }
                }
            }
            if source == .systemAudio || source == .meeting {
                guard let appAudio, let appTarget else {
                    throw AudioCaptureError.deviceUnavailable("No app-audio source was chosen.")
                }
                let session = try appAudio.start(target: appTarget)
                systemSession = session
                systemTask = Task { [weak self] in
                    for await chunk in session.samples { await self?.consumeSystem(chunk) }
                }
            }
        } catch {
            // A partial bring-up must not leak (upstream #213 lesson).
            tearDown()
            try? writer?.close()
            writer = nil
            fileURL = nil
            throw error
        }
        startTime = Date()
        pausedAt = nil
        totalPaused = 0
        captureEpoch += 1
        state = .recording
    }

    public func pause() {
        guard state == .recording else { return }
        pausedAt = Date()
        state = .paused
        // Whatever is parked was produced before the pause: write it out.
        let tail = mixer.drainTail()
        emit(tail)
        micLevel = 0
        systemLevel = 0
    }

    public func resume() {
        guard state == .paused else { return }
        if let pausedAt { totalPaused += Date().timeIntervalSince(pausedAt) }
        pausedAt = nil
        // Anything that slipped in while paused predates the gap; drop it.
        mixer.discardPending()
        state = .recording
    }

    @discardableResult
    public func stop() -> URL? {
        guard state == .recording || state == .paused else { return fileURL }
        state = .stopping
        lastMicFrameCount = micSession?.capturedFrameCount ?? 0
        tearDown()
        emit(mixer.drainTail())
        try? writer?.close()
        writer = nil
        let url = fileURL
        fileURL = nil
        startTime = nil
        pausedAt = nil
        totalPaused = 0
        state = .idle
        return url
    }

    public func cancelAll() {
        guard state != .idle else { return }
        tearDown()
        try? writer?.close()
        writer = nil
        fileURL = nil
        startTime = nil
        mixer.discardPending()
        state = .idle
    }

    // MARK: - Mixing

    func consumeMic(_ samples: [Float]) {
        guard state == .recording else { return }
        micLevel = Self.level(samples)
        if source == .microphone {
            emit(samples)
            return
        }
        emit(mixer.mix(mic: samples))
    }

    func consumeSystem(_ samples: [Float]) {
        guard state == .recording else { return }
        systemLevel = Self.level(samples)
        if source == .systemAudio {
            emit(samples)
            return
        }
        let overflow = mixer.park(system: samples)
        if !overflow.isEmpty { emit(overflow) }
    }

    private func emit(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        onLiveSamples?(samples)
        try? writer?.write(samples)
    }

    private func tearDown() {
        micTask?.cancel(); micTask = nil
        systemTask?.cancel(); systemTask = nil
        micSession?.stop(); micSession = nil
        systemSession?.stop(); systemSession = nil
    }

    static func level(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return min(1, (sum / Float(samples.count)).squareRoot() * 4)
    }
}
