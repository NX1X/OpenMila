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

/// The watchdog policy: upstream's types, brought into the port because the
/// file that holds them upstream is excluded from this build. These test the
/// policy exactly, with an injected clock and no sleeping.
final class CaptureWatchdogTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func test_a_moving_frame_count_is_never_a_stall() {
        var detector = CaptureStallDetector(timeout: 12)
        XCTAssertFalse(detector.observe(frames: 0, now: start))
        for second in 1...30 {
            let moved = detector.observe(frames: second * 160,
                                         now: start.addingTimeInterval(Double(second)))
            XCTAssertFalse(moved, "a device delivering audio must never look stalled")
        }
    }

    func test_a_frozen_frame_count_trips_exactly_at_the_timeout() {
        var detector = CaptureStallDetector(timeout: 12)
        _ = detector.observe(frames: 1000, now: start)
        XCTAssertFalse(detector.observe(frames: 1000, now: start.addingTimeInterval(11.9)))
        XCTAssertTrue(detector.observe(frames: 1000, now: start.addingTimeInterval(12)))
    }

    /// A device that opens and never delivers a single buffer is the case
    /// upstream's comment calls out: arming on the first observation is what
    /// makes that trip rather than wait forever.
    func test_a_device_that_never_delivers_anything_still_trips() {
        var detector = CaptureStallDetector(timeout: 5)
        XCTAssertFalse(detector.observe(frames: 0, now: start))
        XCTAssertTrue(detector.observe(frames: 0, now: start.addingTimeInterval(5)))
    }

    func test_reset_times_the_next_stall_from_the_restart() {
        var detector = CaptureStallDetector(timeout: 5)
        _ = detector.observe(frames: 10, now: start)
        XCTAssertTrue(detector.observe(frames: 10, now: start.addingTimeInterval(5)))
        detector.reset()
        XCTAssertFalse(detector.observe(frames: 10, now: start.addingTimeInterval(5.1)),
                       "the clock restarts with the device, not with the dead one's last buffer")
        XCTAssertTrue(detector.observe(frames: 10, now: start.addingTimeInterval(10.2)))
    }

    func test_the_first_restart_is_immediate_and_the_rest_back_off() {
        var throttle = RebuildThrottle(minimumInterval: 1, maximumInterval: 30)
        XCTAssertTrue(throttle.allow(now: start), "the first trouble in a session is acted on at once")
        XCTAssertFalse(throttle.allow(now: start.addingTimeInterval(0.5)))
        XCTAssertTrue(throttle.allow(now: start.addingTimeInterval(1)))
        XCTAssertFalse(throttle.allow(now: start.addingTimeInterval(2.5)))
        XCTAssertTrue(throttle.allow(now: start.addingTimeInterval(3)))
    }

    func test_the_backoff_saturates_rather_than_growing_without_end() {
        var throttle = RebuildThrottle(minimumInterval: 1, maximumInterval: 8)
        var now = start
        for _ in 0..<12 {
            while !throttle.allow(now: now) { now = now.addingTimeInterval(0.5) }
            now = now.addingTimeInterval(0.1)
        }
        XCTAssertEqual(throttle.currentInterval, 8, "the ladder must stop at the ceiling")
    }

    func test_a_quiet_spell_ends_the_burst() {
        var throttle = RebuildThrottle(minimumInterval: 1, maximumInterval: 4)
        XCTAssertTrue(throttle.allow(now: start))
        XCTAssertTrue(throttle.allow(now: start.addingTimeInterval(1)))
        // An unrelated failure an hour later is not part of that burst.
        XCTAssertTrue(throttle.allow(now: start.addingTimeInterval(3600)))
        XCTAssertEqual(throttle.streak, 1)
    }
}
