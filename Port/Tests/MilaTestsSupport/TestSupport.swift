// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `MilaTests/TestSupport.swift`. Upstream's helper writes its WAV
// fixtures with AVAudioFile; this one writes the same files in plain Swift so
// upstream's test cases run unchanged off macOS. Signatures, defaults and the
// generated audio match upstream's.

import Foundation
import TranscriptionCore
@testable import Mila

enum TestSupport {

    static func makeTempRoot(label: String = "MilaTests") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID())", isDirectory: true)
    }

    /// 16 kHz mono Float32 sine WAV, the canonical Whisper input format.
    @discardableResult
    static func writeSineWav(at url: URL,
                             durationSeconds: Double = 1.0,
                             frequencyHz: Double = 440,
                             amplitude: Float = 0.3) throws -> URL {
        let sampleRate = WhisperAudioFormat.sampleRate
        let frames = Int(sampleRate * durationSeconds)
        let twoPi = 2.0 * Double.pi
        let samples = (0..<frames).map { i in
            Float(sin(twoPi * frequencyHz * Double(i) / sampleRate)) * amplitude
        }
        try writeFloatWAV(interleaved: samples, channels: 1, sampleRate: UInt32(sampleRate), to: url)
        return url
    }

    /// 48 kHz stereo Float32 sine WAV, for the downmix and resample paths.
    @discardableResult
    static func writeStereo48kSineWav(at url: URL,
                                      durationSeconds: Double = 1.0,
                                      frequencyHz: Double = 220,
                                      amplitude: Float = 0.4) throws -> URL {
        let frames = Int(48_000 * durationSeconds)
        let twoPi = 2.0 * Double.pi
        var interleaved = [Float]()
        interleaved.reserveCapacity(frames * 2)
        for i in 0..<frames {
            let value = Float(sin(twoPi * frequencyHz * Double(i) / 48_000.0)) * amplitude
            interleaved.append(value)
            interleaved.append(value)
        }
        try writeFloatWAV(interleaved: interleaved, channels: 2, sampleRate: 48_000, to: url)
        return url
    }

    @MainActor
    static func installFakeModel(into manager: ModelManager,
                                 model: WhisperModel = .ivritLarge) throws {
        manager.setSelected(model)
        let url = manager.url(for: model)
        try Data("not-a-real-model-just-for-tests".utf8).write(to: url)
        manager.refreshInstalled()
    }

    @MainActor
    static func isolatedRemoteSettings(label: String) -> RemoteTranscriptionSettings {
        let suiteName = "\(label).remote"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return RemoteTranscriptionSettings(defaults: suite)
    }

    @MainActor
    static func isolatedModelManager(modelsDirectory: URL, label: String) -> ModelManager {
        let suiteName = "\(label).models"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return ModelManager(modelsDirectory: modelsDirectory, defaults: suite)
    }

    private static func writeFloatWAV(interleaved: [Float], channels: UInt16,
                                      sampleRate: UInt32, to url: URL) throws {
        let blockAlign = channels * 4
        let dataBytes = UInt32(interleaved.count * 4)
        var data = Data(capacity: 44 + Int(dataBytes))
        func le<T: FixedWidthInteger>(_ value: T) {
            Swift.withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8)); le(UInt32(36) + dataBytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); le(UInt32(16))
        le(UInt16(3)); le(channels); le(sampleRate)
        le(sampleRate * UInt32(blockAlign)); le(blockAlign); le(UInt16(32))
        data.append(contentsOf: Array("data".utf8)); le(dataBytes)
        interleaved.withUnsafeBufferPointer { data.append($0) }
        try data.write(to: url)
    }
}

@MainActor
struct TestRecordingFixture {
    let recording: Recording
    let audioURL: URL

    static func make(in store: RecordingStore,
                     title: String = "Test Recording",
                     durationSeconds: Double = 0.5,
                     source: RecordingSource = .microphone,
                     language: String = "he") throws -> TestRecordingFixture {
        let audioURL = store.freshAudioURL(suggestedName: title)
        try TestSupport.writeSineWav(at: audioURL, durationSeconds: durationSeconds)
        let recording = Recording(
            title: title,
            duration: durationSeconds,
            source: source,
            audioFileName: audioURL.lastPathComponent,
            language: language
        )
        store.add(recording)
        return TestRecordingFixture(recording: recording, audioURL: audioURL)
    }
}
