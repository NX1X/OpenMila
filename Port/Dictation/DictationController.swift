// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `Mila/Dictation/DictationController.swift`. Same flow: a
// hotkey (or button) starts capture, the live transcriber feeds partial text,
// the same hotkey stops, one final whisper pass over everything captured
// produces the text, which is injected at the cursor and saved as a
// "Dictation" recording. Capture, hotkeys and injection come from PlatformKit.

import Foundation
import PlatformKit
import TranscriptionCore
@testable import Mila

public enum DictationLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case hebrew = "he"

    public var displayName: String { self == .english ? "English dictation" : "Hebrew dictation" }
    var hotkeyID: String { "dictate.\(rawValue)" }
}

@MainActor
public final class DictationController: ObservableObject {
    public enum State: Equatable { case idle, recording(DictationLanguage), transcribing(DictationLanguage) }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var level: Float = 0
    @Published public private(set) var lastLanguage: DictationLanguage = .hebrew
    @Published public private(set) var lastOutcome: String?

    private let microphone: MicrophoneCapture
    private let injector: TextInjector?
    private let notifier: Notifier
    private let store: RecordingStore
    private let transcription: TranscriptionService
    private let liveTranscriber: LiveTranscriber
    private let audioInput: AudioInputSettings
    private var session: AudioCaptureSession?
    private var streamTask: Task<Void, Never>?
    private var samples: [Float] = []
    private var isStarting = false

    public init(microphone: MicrophoneCapture, injector: TextInjector?, notifier: Notifier,
                store: RecordingStore, transcription: TranscriptionService,
                liveTranscriber: LiveTranscriber, audioInput: AudioInputSettings) {
        self.microphone = microphone
        self.injector = injector
        self.notifier = notifier
        self.store = store
        self.transcription = transcription
        self.liveTranscriber = liveTranscriber
        self.audioInput = audioInput
    }

    public func toggle(_ language: DictationLanguage) async {
        switch state {
        case .idle:
            await start(language)
        case .recording(let active) where active == language:
            await stopAndTranscribe(language)
        case .recording, .transcribing:
            notifier.beep()
        }
    }

    public func cancelInFlight() {
        guard case .recording = state else { return }
        streamTask?.cancel(); streamTask = nil
        session?.stop(); session = nil
        _ = liveTranscriber.stop()
        samples.removeAll()
        state = .idle
        level = 0
    }

    private func start(_ language: DictationLanguage) async {
        guard !isStarting else { notifier.beep(); return }
        isStarting = true
        defer { isStarting = false }
        samples.removeAll(keepingCapacity: true)
        do {
            let deviceID = audioInput.preferredUID.flatMap { $0.isEmpty ? nil : $0 }
            let session = try microphone.start(deviceID: deviceID)
            self.session = session
            state = .recording(language)
            lastLanguage = language
            lastOutcome = nil
            liveTranscriber.start(language: language.rawValue)
            streamTask = Task { [weak self] in
                for await chunk in session.samples {
                    guard let self else { return }
                    self.samples.append(contentsOf: chunk)
                    self.level = RecordingSessionLevel.level(chunk)
                    self.liveTranscriber.ingest(chunk[chunk.startIndex..<chunk.endIndex])
                }
            }
        } catch {
            notifier.beep()
            lastOutcome = error.localizedDescription
        }
    }

    private func stopAndTranscribe(_ language: DictationLanguage) async {
        session?.stop(); session = nil
        streamTask?.cancel(); streamTask = nil
        state = .transcribing(language)
        let captured = samples
        samples.removeAll(keepingCapacity: true)
        _ = liveTranscriber.stop()

        // Full pass over everything captured, no audio_ctx truncation (upstream's
        // reasoning: the live window only holds the last ~20 s).
        let text = await transcription.transcribeOnce(samples: captured, language: language.rawValue, audioCtx: 0)
        state = .idle
        level = 0

        if text.isEmpty {
            notifier.beep()
            lastOutcome = "No speech recognised."
        } else if let injector {
            switch await injector.inject(text) {
            case .injected: lastOutcome = "Pasted."
            case .leftOnClipboard: lastOutcome = "Copied to the clipboard. Press Ctrl+V to paste."
            case .failed(let why): lastOutcome = why
            }
        } else {
            lastOutcome = text
        }
        await persist(samples: captured, text: text, language: language)
    }

    private func persist(samples: [Float], text: String, language: DictationLanguage) async {
        guard !samples.isEmpty else { return }
        let url = store.freshAudioURL(suggestedName: "Dictation")
        do { try AudioConvert.writeWhisperWAV(samples: samples, to: url) } catch { return }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        let recording = Recording(
            title: "Dictation \(f.string(from: Date()))",
            duration: Double(samples.count) / WhisperAudioFormat.sampleRate,
            source: .microphone,
            audioFileName: url.lastPathComponent,
            status: text.isEmpty ? .failed : .completed,
            language: language.rawValue,
            segments: text.isEmpty ? [] : [.init(start: 0, end: 0, text: text)],
            fullText: text
        )
        store.add(recording)
    }
}

enum RecordingSessionLevel {
    static func level(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return min(1, (sum / Float(samples.count)).squareRoot() * 4)
    }
}
