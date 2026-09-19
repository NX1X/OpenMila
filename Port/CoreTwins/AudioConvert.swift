// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of the file-level half of `Mila/Audio/AudioUtilities.swift`
// (AVFoundation on macOS). Same names and contracts for the entry points the
// portable core calls: read any supported audio file as 16 kHz mono Float32,
// and write such samples as a Float32 WAV. The buffer-level converters in the
// upstream file belong to the capture layer and live in the platform targets.

import Foundation
import TranscriptionCore

enum AudioConvert {
    /// Decode `url` to Whisper's input format (16 kHz, mono, Float32).
    ///
    /// WAV is decoded in-process by TranscriptionCore's `WAVReader`, which also
    /// downmixes and resamples. Anything else is handed to `AudioCompressor`
    /// to transcode first, so format support has a single owner.
    static func loadAsWhisperSamples(url: URL) throws -> [Float] {
        if url.pathExtension.lowercased() == "wav" {
            return try WAVReader.loadSamples(url: url)
        }
        let wav = try AudioCompressor.decodeToTempWAV(url)
        defer { try? FileManager.default.removeItem(at: wav) }
        return try WAVReader.loadSamples(url: wav)
    }

    /// Write samples as a canonical 44-byte-header IEEE-float WAV: mono,
    /// `WhisperAudioFormat.sampleRate`, 32 bits per sample, little-endian. The
    /// same layout upstream's AVAudioFile path produces, so files are
    /// interchangeable with recordings made on macOS.
    static func writeWhisperWAV(samples: [Float], to url: URL) throws {
        let sampleRate = UInt32(WhisperAudioFormat.sampleRate)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 32
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataBytes = UInt32(samples.count * MemoryLayout<Float>.size)

        var data = Data(capacity: 44 + Int(dataBytes))
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLE(UInt32(36) + dataBytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(3)) // WAVE_FORMAT_IEEE_FLOAT
        data.appendLE(channels)
        data.appendLE(sampleRate)
        data.appendLE(byteRate)
        data.appendLE(blockAlign)
        data.appendLE(bitsPerSample)
        data.append(contentsOf: Array("data".utf8))
        data.appendLE(dataBytes)
        samples.withUnsafeBufferPointer { buffer in
            // Every supported target is little-endian, which is what WAV wants.
            data.append(UnsafeBufferPointer(start: buffer.baseAddress, count: buffer.count))
        }
        try data.write(to: url, options: .atomic)
    }
}

/// Predicates about a raw sample buffer. Identical to upstream's definition,
/// which sits in the AVFoundation-bound file the port excludes.
enum AudioSignal {
    /// True when capture produced nothing at all: no samples, or exact zeros.
    static func isSilent(_ samples: [Float]) -> Bool {
        !samples.contains { $0 != 0 }
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
