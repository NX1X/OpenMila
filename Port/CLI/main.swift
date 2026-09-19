// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Headless harness: exercises capture and transcription without any UI.
//
//   openmila-cli devices
//   openmila-cli record --seconds 5 --lang en --model ~/.cache/whisper-models/ggml-tiny.bin [--device ID] [--out file.wav]
//   openmila-cli transcribe file.wav --lang he --model <path>

import AudioCapture
import Foundation
import OpenMilaLogging
import PlatformKit
import TranscriptionCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func transcribe(_ samples: [Float], language: String, modelPath: String) async {
    let engine = WhisperEngine()
    do {
        let url = URL(fileURLWithPath: (modelPath as NSString).expandingTildeInPath)
        try await engine.loadIfNeeded(modelURL: url, displayName: url.lastPathComponent)
        let segments = try await engine.transcribe(samples: samples, language: language, audioCtx: 0,
                                                   progress: nil, isCancelled: nil)
        for segment in segments {
            print(String(format: "[%6.2f - %6.2f] %@", segment.start, segment.end,
                         segment.text.trimmingCharacters(in: .whitespaces)))
        }
        if segments.isEmpty { print("(no speech recognised)") }
        await engine.shutdown()
    } catch {
        fail("transcription failed: \(error.localizedDescription)")
    }
}

func writeWAV(_ samples: [Float], to path: String) throws {
    var data = Data()
    func le<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    let bytes = UInt32(samples.count * 4)
    data.append(contentsOf: Array("RIFF".utf8)); le(UInt32(36) + bytes)
    data.append(contentsOf: Array("WAVEfmt ".utf8)); le(UInt32(16)); le(UInt16(3)); le(UInt16(1))
    le(UInt32(16_000)); le(UInt32(64_000)); le(UInt16(4)); le(UInt16(32))
    data.append(contentsOf: Array("data".utf8)); le(bytes)
    samples.withUnsafeBufferPointer { data.append($0) }
    try data.write(to: URL(fileURLWithPath: path))
}

let args = Array(CommandLine.arguments.dropFirst())
OpenMilaLog.install(processName: "openmila-cli", version: "0.0.0-dev", alsoStderr: false)
let microphone = MiniaudioMicrophone()

switch args.first {
case "devices":
    do {
        let devices = try microphone.inputDevices()
        if devices.isEmpty { print("no capture devices") }
        for device in devices {
            print("\(device.isDefault ? "*" : " ") \(device.name)\n    id: \(device.id)")
        }
        let system = try MiniaudioSystemLoopback().targets()
        print("system-audio targets: \(system.isEmpty ? "none" : system.map(\.name).joined(separator: ", "))")
    } catch { fail("\(error.localizedDescription)") }

case "record":
    let seconds = Double(option("--seconds", in: args) ?? "5") ?? 5
    let language = option("--lang", in: args) ?? "en"
    do {
        let session = try microphone.start(deviceID: option("--device", in: args))
        print("recording \(seconds)s via \(session.backendName)...")
        var captured: [Float] = []
        let target = Int(seconds * PlatformAudioFormat.sampleRate)
        let deadline = Date().addingTimeInterval(seconds + 5)
        for await chunk in session.samples {
            captured.append(contentsOf: chunk)
            if captured.count >= target || Date() > deadline { break }
        }
        session.stop()
        let peak = captured.map { abs($0) }.max() ?? 0
        print("captured \(captured.count) samples (\(String(format: "%.2f", Double(captured.count) / 16_000))s), peak \(String(format: "%.3f", peak))")
        if let out = option("--out", in: args) { try writeWAV(captured, to: out) }
        guard !captured.isEmpty else { fail("no audio captured") }
        if let model = option("--model", in: args) {
            await transcribe(captured, language: language, modelPath: model)
        }
    } catch { fail("\(error.localizedDescription)") }

case "logs":
    // Where a bug report's logs come from. Prints the directory and the tail.
    print("log directory: \(OpenMilaLog.defaultDirectory.path)")
    if let text = try? String(contentsOf: OpenMilaLog.currentFile, encoding: .utf8) {
        print(text.split(separator: "\n").suffix(40).joined(separator: "\n"))
    } else {
        print("(no log file yet)")
    }

case "transcribe":
    guard args.count >= 2, let model = option("--model", in: args) else {
        fail("usage: openmila-cli transcribe <file.wav> --model <path> [--lang en]")
    }
    do {
        let samples = try WAVReader.loadSamples(url: URL(fileURLWithPath: args[1]))
        await transcribe(samples, language: option("--lang", in: args) ?? "en", modelPath: model)
    } catch { fail("\(error.localizedDescription)") }

default:
    print("usage: openmila-cli devices | logs | record [--seconds N] [--lang en|he] [--model path] [--device id] [--out file.wav] | transcribe <file.wav> --model path [--lang en|he]")
}
