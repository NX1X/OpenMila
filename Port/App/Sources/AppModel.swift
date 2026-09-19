// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// The port's counterpart of `MilaApp.init`: constructs upstream's core
// objects in the same order and with the same dependencies, and adds the
// platform services. Everything is `@MainActor`, as upstream's are.

import AudioCapture
import Foundation
import LinuxPlatform
import OpenMilaLogging
import PlatformKit
import Recording
import TranscriptionCore
@testable import Mila

enum AppIdentity {
    static let name = "OpenMila"
    static let version = "1.9.5+port.0-dev"
    static let upstreamVersion = "1.9.5-beta.2"
    static let repository = "NX1X/OpenMila"
}

@MainActor
final class AppModel {
    let platform: PlatformServices
    let store: RecordingStore
    let storageSettings: RecordingStorageSettings
    let modelManager: ModelManager
    let languageSettings: RecordingLanguageSettings
    let diarizationSettings: DiarizationSettings
    let remoteSettings: RemoteTranscriptionSettings
    let transcription: TranscriptionService
    let liveTranscriber: LiveTranscriber
    let session: RecordingSession
    let llmSettings: LLMSettings
    let mcpAccess: MCPAccessSettings
    let audioInput: AudioInputSettings
    let speakerDirectory: SpeakerDirectory
    let voiceRecognition: VoiceRecognitionSettings
    let speakerProfiles: SpeakerProfileStore
    let meetingDetection: MeetingDetectionSettings
    let watchedFolders: VoiceMemosSettings

    init() {
        OpenMilaLog.install(processName: AppIdentity.name, version: AppIdentity.version)
        platform = LinuxPlatform.services(appVersion: AppIdentity.version)
        try? FileManager.default.createDirectory(at: platform.paths.dataDirectory, withIntermediateDirectories: true)

        storageSettings = RecordingStorageSettings()
        store = RecordingStore(rootDirectory: platform.paths.dataDirectory,
                               customRecordingsDirectory: storageSettings.customDirectory)
        modelManager = ModelManager(modelsDirectory: platform.paths.dataDirectory.appendingPathComponent("Models", isDirectory: true))
        languageSettings = RecordingLanguageSettings()
        diarizationSettings = DiarizationSettings()
        remoteSettings = RemoteTranscriptionSettings()
        transcription = TranscriptionService(store: store, modelManager: modelManager,
                                             diarizationSettings: diarizationSettings,
                                             remoteSettings: remoteSettings)
        liveTranscriber = LiveTranscriber(transcription: transcription)
        session = RecordingSession(microphone: platform.microphone, appAudio: platform.appAudio)
        llmSettings = LLMSettings()
        mcpAccess = MCPAccessSettings()
        audioInput = AudioInputSettings()
        speakerDirectory = SpeakerDirectory(directory: platform.paths.dataDirectory)
        voiceRecognition = VoiceRecognitionSettings()
        speakerProfiles = SpeakerProfileStore(directory: platform.paths.dataDirectory, settings: voiceRecognition)
        meetingDetection = MeetingDetectionSettings()
        watchedFolders = VoiceMemosSettings()

        session.onLiveSamples = { [liveTranscriber] samples in
            liveTranscriber.ingest(samples[samples.startIndex..<samples.endIndex])
        }
    }

    // MARK: Recording flow (upstream: QuickActionsController.startRecording / stopRecording)

    private(set) var currentRecordingURL: URL?
    private(set) var currentRecordingStart: Date?

    func startRecording(source: CaptureSource, appTarget: AudioCaptureTarget?) throws {
        guard session.state == .idle else { return }
        let url = store.freshAudioURL(suggestedName: "Recording")
        try session.start(source: source, outputURL: url, micDeviceID: audioInput.selectedDeviceID, appTarget: appTarget)
        currentRecordingURL = url
        currentRecordingStart = Date()
        liveTranscriber.start(language: languageSettings.current.rawValue)
        platform.sleep.acquire(reason: "Recording")
    }

    func stopRecording() {
        platform.sleep.release()
        guard let url = session.stop() else { return }
        _ = liveTranscriber.stop()
        let duration = (try? WAVReader.loadSamples(url: url).count).map { Double($0) / WhisperAudioFormat.sampleRate } ?? 0
        if session.lastMicFrameCount == 0 && session.source != .systemAudio {
            transcription.lastError = "No audio was captured from the microphone. Check the input in Settings > Audio."
        }
        if storageSettings.shouldAutoDrop(duration: duration, transcript: liveTranscriber.fullText) {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let source: Mila.RecordingSource
        switch session.source {
        case .microphone: source = .microphone
        case .systemAudio: source = .systemAudio
        case .meeting: source = .meeting
        }
        let recording = Mila.Recording(
            title: Self.defaultTitle(for: currentRecordingStart ?? Date()),
            createdAt: currentRecordingStart ?? Date(),
            duration: duration,
            source: source,
            audioFileName: url.lastPathComponent,
            language: languageSettings.current.rawValue
        )
        store.add(recording)
        transcription.enqueue(recording)
        currentRecordingURL = nil
    }

    static func defaultTitle(for date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "Recording \(f.string(from: date))"
    }
}

extension AudioInputSettings {
    /// Upstream stores a CoreAudio device UID; the port stores miniaudio's id
    /// under the same key, so an empty value means "system default".
    var selectedDeviceID: String? {
        guard let id = preferredUID, !id.isEmpty else { return nil }
        return id
    }
}
