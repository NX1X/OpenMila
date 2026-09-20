// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `Mila/Audio/FileTranscriber.swift` (AVFoundation re-encode).
// Same signature and steps: copy an audio file into the store as 16 kHz mono
// Float32 WAV, create the folder if asked, add the recording, enqueue it.
// Decoding goes through `AudioConvert` (WAV in-process, ffmpeg otherwise).

import Foundation
import TranscriptionCore

@MainActor
enum FileTranscriber {

    static func importFile(at sourceURL: URL,
                           into store: RecordingStore,
                           language: RecordingLanguage = .hebrew,
                           source: RecordingSource = .systemAudio,
                           title titleOverride: String? = nil,
                           createdAt: Date? = nil,
                           voiceMemoUniqueID: String? = nil,
                           voiceMemoFolderUUID: String? = nil,
                           folder: String? = nil) async throws -> Recording {
        let title = titleOverride ?? sourceURL.deletingPathExtension().lastPathComponent
        let safeStem = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let destURL = store.freshAudioURL(suggestedName: safeStem)

        let duration = try await reencode(source: sourceURL, destination: destURL)

        if let folder { store.createFolder(folder) }

        let recording = Recording(
            title: title,
            createdAt: createdAt ?? Date(),
            duration: duration,
            source: source,
            audioFileName: destURL.lastPathComponent,
            language: language.rawValue,
            folder: folder,
            voiceMemoUniqueID: voiceMemoUniqueID,
            voiceMemoFolderUUID: voiceMemoFolderUUID
        )
        store.add(recording)
        return recording
    }

    /// Decode off the main actor and write the canonical WAV. Returns the
    /// duration in seconds.
    private static func reencode(source: URL, destination: URL) async throws -> Double {
        try await Task.detached(priority: .userInitiated) {
            let samples = try AudioConvert.loadAsWhisperSamples(url: source)
            try AudioConvert.writeWhisperWAV(samples: samples, to: destination)
            return Double(samples.count) / WhisperAudioFormat.sampleRate
        }.value
    }
}
