// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// The time stretcher behind playback speed: it must change the DURATION and
// leave the PITCH alone. Upstream gets that from AVAudioUnitTimePitch; the
// port has to prove it for itself.

import CMiniaudio
import XCTest

/// Source audio handed to the stretcher through its C fill callback.
private final class Source {
    let samples: [Float]
    var offset = 0
    init(_ samples: [Float]) { self.samples = samples }
}

private let fill: om_stretch_fill = { user, destination, frames in
    let source = Unmanaged<Source>.fromOpaque(user!).takeUnretainedValue()
    let available = source.samples.count - source.offset
    let take = min(Int(frames), max(0, available))
    if take > 0 {
        source.samples.withUnsafeBufferPointer { buffer in
            destination!.update(from: buffer.baseAddress! + source.offset, count: take)
        }
        source.offset += take
    }
    return UInt64(take)
}

final class StretchTests: XCTestCase {
    private let sampleRate = 16_000

    private func sine(hz: Double, seconds: Double) -> [Float] {
        let count = Int(Double(sampleRate) * seconds)
        return (0..<count).map { Float(sin(2 * .pi * hz * Double($0) / Double(sampleRate))) }
    }

    /// Zero crossings per second, which for a sine is twice its frequency.
    /// Good enough to tell 440 Hz from the 660 Hz a resampler would produce
    /// at 1.5x, and it needs no FFT.
    private func frequency(of samples: [Float]) -> Double {
        var crossings = 0
        for i in 1..<samples.count where (samples[i - 1] < 0) != (samples[i] < 0) { crossings += 1 }
        return Double(crossings) / 2 / (Double(samples.count) / Double(sampleRate))
    }

    private func stretch(_ input: [Float], rate: Double) -> [Float] {
        guard let stretcher = om_stretch_create(UInt32(sampleRate), 1) else { return [] }
        defer { om_stretch_destroy(stretcher) }
        om_stretch_set_rate(stretcher, rate)
        let source = Source(input)
        let user = Unmanaged.passUnretained(source).toOpaque()
        var output: [Float] = []
        var block = [Float](repeating: 0, count: 1024)
        while true {
            let written = block.withUnsafeMutableBufferPointer { buffer in
                om_stretch_read(stretcher, buffer.baseAddress!, 1024, fill, user)
            }
            if written == 0 { break }
            output.append(contentsOf: block.prefix(Int(written)))
            if written < 1024 { break }
        }
        return output
    }

    func test_faster_playback_shortens_the_audio() {
        let input = sine(hz: 440, seconds: 2)
        let output = stretch(input, rate: 1.5)
        let expected = Double(input.count) / 1.5
        XCTAssertEqual(Double(output.count), expected, accuracy: expected * 0.1)
    }

    func test_slower_playback_lengthens_the_audio() {
        let input = sine(hz: 440, seconds: 2)
        let output = stretch(input, rate: 0.5)
        let expected = Double(input.count) / 0.5
        XCTAssertEqual(Double(output.count), expected, accuracy: expected * 0.1)
    }

    func test_pitch_survives_a_speed_change() {
        let input = sine(hz: 440, seconds: 2)
        for rate in [0.5, 0.75, 1.5, 2.0] {
            let output = stretch(input, rate: rate)
            XCTAssertGreaterThan(output.count, sampleRate / 2, "rate \(rate) produced almost nothing")
            // A resampler would report 440 * rate here; the stretcher must not.
            XCTAssertEqual(frequency(of: Array(output.dropFirst(sampleRate / 4))), 440,
                           accuracy: 30, "pitch moved at \(rate)x")
        }
    }

    func test_unchanged_speed_passes_the_audio_through() {
        let input = sine(hz: 440, seconds: 1)
        let output = stretch(input, rate: 1.0)
        XCTAssertEqual(output.count, input.count)
        for (a, b) in zip(input.prefix(1000), output.prefix(1000)) { XCTAssertEqual(a, b, accuracy: 1e-6) }
    }
}
