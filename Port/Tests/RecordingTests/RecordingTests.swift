// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import Foundation
import PlatformKit
import TranscriptionCore
import XCTest
@testable import Recording

/// A capture backend driven by the test.
final class FakeSession: AudioCaptureSession, @unchecked Sendable {
    let samples: AsyncStream<[Float]>
    let continuation: AsyncStream<[Float]>.Continuation
    let backendName = "fake"
    var capturedFrameCount = 0
    init() {
        var c: AsyncStream<[Float]>.Continuation!
        samples = AsyncStream { c = $0 }
        continuation = c
    }
    func push(_ chunk: [Float]) { capturedFrameCount += chunk.count; continuation.yield(chunk) }
    func stop() { continuation.finish() }
}

struct FakeMicrophone: MicrophoneCapture {
    let session: FakeSession
    func inputDevices() throws -> [AudioInputDevice] { [] }
    func start(deviceID: String?) throws -> AudioCaptureSession { session }
}

struct FakeAppAudio: AppAudioCapture {
    let session: FakeSession
    func targets() throws -> [AudioCaptureTarget] { [] }
    func start(target: AudioCaptureTarget) throws -> AudioCaptureSession { session }
}

final class WAVFileWriterTests: XCTestCase {
    func test_streamed_file_reads_back_through_upstream_reader() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID()).wav")
        let writer = try WAVFileWriter(url: url)
        let a: [Float] = [0.1, 0.2, 0.3]
        let b: [Float] = [-0.5, 0.5]
        try writer.write(a)
        try writer.write(b)
        try writer.close()
        let back = try WAVReader.loadSamples(url: url)
        XCTAssertEqual(back.count, 5)
        XCTAssertEqual(back[3], -0.5, accuracy: 1e-6)
        try? FileManager.default.removeItem(at: url)
    }

    func test_unclosed_file_has_placeholder_sizes_that_repair_expects() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID()).wav")
        let writer = try WAVFileWriter(url: url)
        try writer.write([Float](repeating: 0.25, count: 1_000))
        // No close: simulate a crash. Header still says 0 data bytes.
        let data = try Data(contentsOf: url)
        let dataSize = data[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(dataSize, 0)
        XCTAssertEqual(data.count, 44 + 4_000)
        try writer.close()
        try? FileManager.default.removeItem(at: url)
    }
}

final class MeetingMixerTests: XCTestCase {
    func test_overlap_is_averaged_and_mic_alone_stays_full_scale() {
        var mixer = MeetingMixer()
        XCTAssertTrue(mixer.park(system: [0.4, 0.4]).isEmpty)
        let mixed = mixer.mix(mic: [0.2, 0.2, 0.2, 0.2])
        XCTAssertEqual(mixed, [0.3, 0.3, 0.2, 0.2])
        XCTAssertTrue(mixer.pendingSystem.isEmpty)
    }

    func test_overflow_is_flushed_not_dropped() {
        var mixer = MeetingMixer()
        let big = [Float](repeating: 0.1, count: MeetingMixer.maxPending + 100)
        let overflow = mixer.park(system: big)
        XCTAssertEqual(overflow.count, 100)
        XCTAssertEqual(mixer.pendingSystem.count, MeetingMixer.maxPending)
        XCTAssertEqual(mixer.overflowFlushes, 1)
    }
}

@MainActor
final class RecordingSessionTests: XCTestCase {
    func test_meeting_recording_writes_mix_and_pause_drops_audio() async throws {
        let mic = FakeSession(), sys = FakeSession()
        let session = RecordingSession(microphone: FakeMicrophone(session: mic),
                                       appAudio: FakeAppAudio(session: sys))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("r-\(UUID()).wav")
        var live: [Float] = []
        session.onLiveSamples = { live.append(contentsOf: $0) }
        try session.start(source: .meeting, outputURL: url,
                          appTarget: AudioCaptureTarget(id: "x", name: "x", scope: .wholeSystem))
        XCTAssertEqual(session.state, .recording)

        // Direct calls keep the test deterministic (no task scheduling).
        session.consumeSystem([0.4, 0.4])
        session.consumeMic([0.2, 0.2, 0.2])
        session.pause()
        session.consumeMic([0.9, 0.9])          // dropped
        session.resume()
        session.consumeMic([0.1])
        let out = session.stop()

        XCTAssertEqual(out, url)
        XCTAssertEqual(session.state, .idle)
        let back = try WAVReader.loadSamples(url: url)
        XCTAssertEqual(back.count, 4)
        XCTAssertEqual(back[0], 0.3, accuracy: 1e-6)
        XCTAssertEqual(back[2], 0.2, accuracy: 1e-6)
        XCTAssertEqual(back[3], 0.1, accuracy: 1e-6)
        XCTAssertEqual(live.count, 4)
        try? FileManager.default.removeItem(at: url)
    }

    func test_failed_bring_up_leaves_no_file_and_stays_idle() async {
        struct Broken: MicrophoneCapture {
            func inputDevices() throws -> [AudioInputDevice] { [] }
            func start(deviceID: String?) throws -> AudioCaptureSession {
                throw AudioCaptureError.deviceUnavailable("no mic")
            }
        }
        let session = RecordingSession(microphone: Broken(), appAudio: nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("r-\(UUID()).wav")
        XCTAssertThrowsError(try session.start(source: .microphone, outputURL: url))
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.fileURL)
        try? FileManager.default.removeItem(at: url)
    }
}
