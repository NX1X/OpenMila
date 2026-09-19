// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port of `Mila/Views/HomeView.swift` + the record controls from
// `QuickActionsController`: source, language, record / pause / stop, live
// transcript.

import Dictation
import Foundation
import PlatformKit
import Recording
import SwiftCrossUI
@testable import Mila

struct HomeView: View {
    let model: AppModel
    let transcription: Observed<TranscriptionService>
    @State var live: Observed<LiveTranscriber>
    @State var language: Observed<RecordingLanguageSettings>
    @State var dictation: Observed<DictationController>
    @State var tick = 0
    @State var sourceName: String? = "Microphone"
    @State var targetName: String? = nil
    @State var error: String?

    init(model: AppModel, transcription: Observed<TranscriptionService>) {
        self.model = model
        self.transcription = transcription
        _live = State(wrappedValue: Observed(model.liveTranscriber))
        _language = State(wrappedValue: Observed(model.languageSettings))
        _dictation = State(wrappedValue: Observed(model.dictation))
    }

    var targets: [AudioCaptureTarget] { (try? model.platform.appAudio?.targets()) ?? [] }

    var isRecording: Bool { model.session.state == .recording || model.session.state == .paused }

    func start() {
        error = nil
        let source: CaptureSource
        switch sourceName {
        case "System audio": source = .systemAudio
        case "Meeting (mic + system)": source = .meeting
        default: source = .microphone
        }
        let target = targets.first { $0.name == targetName } ?? targets.first
        do { try model.startRecording(source: source, appTarget: target) }
        catch { self.error = error.localizedDescription }
        tick += 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record").font(.title2)
            HStack {
                Text("Source").font(.callout)
                Picker(of: ["Microphone", "System audio", "Meeting (mic + system)"], selection: $sourceName)
                if sourceName != "Microphone" {
                    Picker(of: targets.map(\.name), selection: $targetName)
                }
                Text("Language").font(.callout)
                Picker(of: RecordingLanguage.allCases.map(\.displayName),
                       selection: Binding(
                           get: { language.object.current.displayName },
                           set: { name in
                               if let lang = RecordingLanguage.allCases.first(where: { $0.displayName == name }) {
                                   language.object.current = lang
                               }
                           }))
            }
            HStack(spacing: 12) {
                if !isRecording {
                    Button("Record") { start() }
                } else {
                    if model.session.state == .paused {
                        Button("Resume") { model.session.resume(); tick += 1 }
                    } else {
                        Button("Pause") { model.session.pause(); tick += 1 }
                    }
                    Button("Stop") { model.stopRecording(); tick += 1 }
                    Text(Self.clock(model.session.elapsed)).font(.title3)
                    Text(model.session.state == .paused ? "Paused" : "Recording")
                        .foregroundColor(Theme.recording).font(.callout)
                }
            }
            if let error { Text(error).foregroundColor(Theme.danger).font(.callout) }
            Divider()
            HStack(spacing: 12) {
                Text("Dictate").font(.headline)
                ForEach(DictationLanguage.allCases, id: \.self) { lang in
                    Button(dictationLabel(lang)) { Task { await model.dictation.toggle(lang) } }
                }
                Text(dictationStatus).font(.caption).foregroundColor(Theme.secondaryText)
            }
            if let outcome = dictation.object.lastOutcome { Text(outcome).font(.caption) }
            if let error = transcription.object.lastError {
                Text(error).foregroundColor(Theme.danger).font(.callout)
            }
            if transcription.object.isPreparingModel {
                Text(transcription.object.preparationStatus ?? "Preparing model...").font(.caption)
            }
            Divider()
            Text("Live transcript").font(.headline)
            ScrollView {
                VStack(alignment: live.object.fullText.isRTLText ? .trailing : .leading, spacing: 8) {
                    ForEach(live.object.segments) { segment in
                        Text(segment.text)
                            .font(.body)
                            .multilineTextAlignment(segment.text.isRTLText ? .trailing : .leading)
                            .frame(maxWidth: .infinity, alignment: segment.text.isRTLText ? .trailing : .leading)
                    }
                    if live.object.segments.isEmpty {
                        Text(isRecording ? "Listening..." : "Words appear here while you record.")
                            .foregroundColor(Theme.secondaryText).font(.callout)
                    }
                }.padding()
            }
        }
        .padding()
        .task {
            // Elapsed clock and meters at 5 Hz while recording, like upstream.
            while true {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if isRecording { tick += 1 }
            }
        }
    }

    func dictationLabel(_ lang: DictationLanguage) -> String {
        let chord = model.hotkeys.chord(for: lang).displayName
        switch dictation.object.state {
        case .recording(let active) where active == lang: return "Stop (\(chord))"
        default: return "\(lang == .english ? "EN" : "HE") (\(chord))"
        }
    }

    var dictationStatus: String {
        switch dictation.object.state {
        case .idle: return model.hotkeys.isAvailable ? "Press the hotkey anywhere, or click." : "Hotkeys need an X11 session; click to dictate."
        case .recording: return "Listening... press again to stop and paste."
        case .transcribing: return "Transcribing..."
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
