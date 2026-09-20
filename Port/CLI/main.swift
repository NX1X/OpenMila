// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Headless harness: exercises capture and transcription without any UI.
//
//   openmila-cli devices
//   openmila-cli record --seconds 5 --lang en --model ~/.cache/whisper-models/ggml-tiny.bin [--device ID] [--out file.wav]
//   openmila-cli transcribe file.wav --lang he --model <path>

import AudioCapture
import Foundation
#if os(Windows)
import WindowsPlatform
#else
import LinuxPlatform
#endif
import OpenMilaLogging
import Recording
import Updater
import PlatformKit
import TranscriptionCore

#if os(Windows)
typealias HostPlatform = WindowsPlatform
#else
typealias HostPlatform = LinuxPlatform
#endif

/// The platform's services, built once and shared by the commands that poke at
/// them. Going through `PlatformServices` rather than naming the Linux types
/// keeps this harness identical on both systems.
let host = HostPlatform.services(appVersion: "0.0.0-cli")

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
        let system = try host.appAudio?.targets() ?? []
        print("app-audio targets:")
        if system.isEmpty { print("    none") }
        for target in system {
            let kind: String
            switch target.scope {
            case .application(let pid): kind = "application pid \(pid)"
            case .wholeSystem: kind = "whole system"
            }
            print("    \(target.name)\n        id: \(target.id)  (\(kind))")
        }
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

case "app-audio":
    // Records one application's output (or a whole-system monitor) so the
    // per-app path can be checked without the UI:
    //   openmila-cli app-audio --target 80 --seconds 3 --out /tmp/app.wav
    guard let appAudio = host.appAudio else { fail("this system has no app-audio capture") }
    do {
        let targets = try appAudio.targets()
        guard !targets.isEmpty else { fail("nothing is playing audio") }
        let chosen: AudioCaptureTarget
        if let id = option("--target", in: args) {
            guard let match = targets.first(where: { $0.id == id }) else { fail("no target with id \(id)") }
            chosen = match
        } else {
            chosen = targets[0]
        }
        let seconds = Double(option("--seconds", in: args) ?? "3") ?? 3
        let session = try appAudio.start(target: chosen)
        print("recording \(seconds)s from \(chosen.name) via \(session.backendName)...")
        var captured: [Float] = []
        let wanted = Int(seconds * PlatformAudioFormat.sampleRate)
        let deadline = Date().addingTimeInterval(seconds + 5)
        for await chunk in session.samples {
            captured.append(contentsOf: chunk)
            if captured.count >= wanted || Date() > deadline { break }
        }
        session.stop()
        let peak = captured.map { abs($0) }.max() ?? 0
        print("captured \(captured.count) samples (\(String(format: "%.2f", Double(captured.count) / 16_000))s), peak \(String(format: "%.3f", peak))")
        if let out = option("--out", in: args) { try writeWAV(captured, to: out) }
        guard !captured.isEmpty else { fail("no audio captured") }
    } catch { fail("\(error.localizedDescription)") }

case "gpu":
    // What the machine offers the model, and what the port will do with it.
    // A software Vulkan device (llvmpipe, lavapipe) is reported but refused:
    // running the model on the CPU pretending to be a GPU is slower than the
    // CPU backend itself.
    print("vulkan: \(VulkanAvailability.device.description)")
    print("whisper will use: \(VulkanAvailability.device.isUsableGPU ? "the GPU" : "the CPU")")
    if !VulkanAvailability.device.isUsableGPU {
        print("set OPENMILA_DISABLE_GPU=1 to refuse the GPU even when one is present")
    }

case "logs":
    // Where a bug report's logs come from. Prints the directory and the tail.
    print("log directory: \(OpenMilaLog.defaultDirectory.path)")
    if let text = try? String(contentsOf: OpenMilaLog.currentFile, encoding: .utf8) {
        print(text.split(separator: "\n").suffix(40).joined(separator: "\n"))
    } else {
        print("(no log file yet)")
    }

case "notify":
    host.notifier.notify(title: "OpenMila", body: args.dropFirst().joined(separator: " ").isEmpty ? "Notification test" : args.dropFirst().joined(separator: " "))
    print("sent")

case "inject":
    let text = args.dropFirst().joined(separator: " ")
    guard let injector = host.textInjector else { fail("this system has no text injector") }
    let outcome = await injector.inject(text.isEmpty ? "OpenMila dictation test" : text)
    print("outcome: \(outcome)")

case "inhibit":
    let seconds = Double(option("--seconds", in: args) ?? "5") ?? 5
    let inhibitor = host.sleep
    inhibitor.acquire(reason: "OpenMila CLI test")
    print("sleep inhibited for \(seconds)s (check: systemd-inhibit --list)")
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    inhibitor.release()
    print("released")

case "hotkey":
    guard let hotkeys = host.hotkeys else { fail("this system offers no global shortcuts: no X display, and no desktop portal that implements GlobalShortcuts") }
    print("backend: \(type(of: hotkeys))")
    let chord = HotkeyChord(key: option("--key", in: args) ?? "2", modifiers: [.control, .alt])
    let result = await hotkeys.register(id: "test", chord: chord) { print("pressed \(chord.displayName)") }
    print("register \(chord.displayName): \(result). Waiting 15s for presses...")
    try? await Task.sleep(nanoseconds: 15_000_000_000)
    await hotkeys.unregister(id: "test")

case "windows":
    // What the window-title signal can see on this session. Empty on a pure
    // Wayland session by design: a client cannot see another client's windows.
    let titles = X11WindowTitles.all()
    print("window titles visible: \(titles.count)")
    for title in titles.prefix(25) { print("  \(title)") }

case "meetings":
    guard let signals = host.meetings else { fail("this system has no meeting detection") }
    let found = await signals.activeMeetings()
    print(found.isEmpty ? "no meeting apps running" : found.map(\.appName).joined(separator: ", "))

case "update-check":
    let repo = option("--repo", in: args) ?? HostPlatform.repository
    let updater = GitHubReleasesUpdater(repository: repo, currentVersion: option("--current", in: args) ?? "0.0.0")
    do {
        if let update = try await updater.check(includePrereleases: args.contains("--beta")) {
            print("update available: \(update.version) prerelease=\(update.isPrerelease) \(update.downloadPage)")
        } else { print("up to date") }
    } catch { fail("update check failed: \(error)") }

case "session":
    // Records through the port's RecordingSession (mic, or --system for the
    // whole-system monitor) and writes a WAV.
    let seconds = Double(option("--seconds", in: args) ?? "5") ?? 5
    let out = option("--out", in: args) ?? "openmila-session.wav"
    let system = MiniaudioSystemLoopback()
    let session = await RecordingSession(microphone: microphone, appAudio: system)
    do {
        let target = try system.targets().first
        let source: CaptureSource = args.contains("--system") ? .systemAudio : (args.contains("--meeting") ? .meeting : .microphone)
        try await session.start(source: source, outputURL: URL(fileURLWithPath: out), appTarget: target)
        print("session recording \(source) for \(seconds)s -> \(out)")
        try? await Task.sleep(nanoseconds: UInt64(seconds / 2 * 1_000_000_000))
        await session.pause(); print("paused 1s"); try? await Task.sleep(nanoseconds: 1_000_000_000); await session.resume()
        try? await Task.sleep(nanoseconds: UInt64(seconds / 2 * 1_000_000_000))
        let url = await session.stop()
        let frames = await session.lastMicFrameCount
        print("stopped: \(url?.path ?? "-") micFrames=\(frames) elapsed excludes the pause")
        if let model = option("--model", in: args), let url {
            await transcribe(try WAVReader.loadSamples(url: url), language: option("--lang", in: args) ?? "en", modelPath: model)
        }
    } catch { fail("\(error.localizedDescription)") }

case "play":
    guard args.count >= 2 else { fail("usage: openmila-cli play <file.wav> [--rate 1.5] [--seek 2.0]") }
    do {
        let player = try MiniaudioPlayer(url: URL(fileURLWithPath: args[1]))
        if let rate = option("--rate", in: args).flatMap(Double.init) { player.setRate(rate) }
        if let seek = option("--seek", in: args).flatMap(Double.init) { player.seek(to: seek) }
        print("playing \(String(format: "%.1f", player.duration))s")
        player.play()
        while player.isPlaying { try? await Task.sleep(nanoseconds: 100_000_000) }
        print("finished at \(String(format: "%.1f", player.position))s")
    } catch { fail(error.localizedDescription) }

case "transcribe":
    guard args.count >= 2, let model = option("--model", in: args) else {
        fail("usage: openmila-cli transcribe <file.wav> --model <path> [--lang en]")
    }
    do {
        let samples = try WAVReader.loadSamples(url: URL(fileURLWithPath: args[1]))
        await transcribe(samples, language: option("--lang", in: args) ?? "en", modelPath: model)
    } catch { fail("\(error.localizedDescription)") }

default:
    print("usage: openmila-cli devices | app-audio | gpu | windows | logs | play | notify | inject | inhibit | hotkey | meetings | update-check | session | record [--seconds N] [--lang en|he] [--model path] [--device id] [--out file.wav] | transcribe <file.wav> --model path [--lang en|he]")
}
