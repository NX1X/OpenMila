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
    @State var liveAI: Observed<LiveAISession>
    @State var liveAISettings: Observed<LiveAISettings>
    @State var post: Observed<PostRecordingCoordinator>
    @State var renameDraft = ""
    @State var meeting: Observed<MeetingPrompt>
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
        _liveAI = State(wrappedValue: Observed(model.liveAI))
        _liveAISettings = State(wrappedValue: Observed(model.liveAISettings))
        _post = State(wrappedValue: Observed(model.postRecording))
        _meeting = State(wrappedValue: Observed(model.meetingPrompt))
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
            if let offer = meeting.object.offer {
                HStack {
                    switch offer {
                    case .start(let m):
                        Text("\(m.appName) started. Record this meeting?").font(.callout)
                        Button("Record meeting") { sourceName = "Meeting (mic + system)"; start(); model.meetingPrompt.dismiss() }
                    case .stop(let m):
                        Text("\(m.appName) ended. Stop recording?").font(.callout)
                        Button("Stop") { model.stopRecording(); model.meetingPrompt.dismiss(); tick += 1 }
                    }
                    Button("Not now") { model.meetingPrompt.dismiss() }
                }
            }
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
                        .fixedSize(horizontal: true, vertical: false)
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
            HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading) {
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
            if model.isLiveAIActive || !liveAI.object.summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live AI").font(.headline)
                    Text("Context for this meeting").font(.caption).foregroundColor(Theme.secondaryText)
                    TextEditor(text: Binding(get: { liveAISettings.object.meetingContext },
                                             set: { liveAISettings.object.meetingContext = $0 })).frame(minHeight: 60)
                    if liveAI.object.isThinking { Text("Thinking...").font(.caption) }
                    if let err = liveAI.object.lastError { Text(err).font(.caption).foregroundColor(Theme.danger) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(liveAI.object.summary.isEmpty ? "Summary appears as the meeting goes." : liveAI.object.summary)
                                .font(.callout).multilineTextAlignment(liveAI.object.summary.isRTLText ? .trailing : .leading)
                            ForEach(liveAI.object.actionItems) { item in
                                Text("- \(item.text)").font(.callout)
                            }
                        }
                    }
                }.frame(minWidth: 280)
            }
            }
        }
        .padding()
        .sheet(isPresented: Binding(get: { post.object.pending != nil }, set: { if !$0 { post.object.pending = nil } })) {
            PostRecordingSheet(model: model, post: post)
        }
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


/// Port of `Mila/Views/RenameRecordingSheet.swift` in its post-recording role:
/// the just-finished recording with a suggested title, summary and action items.
struct PostRecordingSheet: View {
    let model: AppModel
    let post: Observed<PostRecordingCoordinator>
    @State var title = ""
    @State var seeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let recording = post.object.pending {
                Text("Recording finished").font(.title3)
                TextField("Title", text: $title)
                    .onAppear { if !seeded { title = recording.title; seeded = true } }
                if let status = post.object.activityStatus {
                    Text(status).font(.caption).foregroundColor(post.object.activityIsError ? Theme.danger : Theme.secondaryText)
                }
                if let summary = recording.summary, !summary.isEmpty {
                    Text("Summary").font(.headline)
                    Text(summary).font(.callout)
                }
                if let items = recording.actionItems, !items.isEmpty {
                    Text("Action items").font(.headline)
                    ForEach(items) { Text("- \($0.text)").font(.callout) }
                }
                HStack {
                    Button("Later") { post.object.pending = nil }
                    Button("Save") {
                        model.store.rename(recording, to: title)
                        post.object.pending = nil
                    }
                }
            }
        }.padding().frame(minWidth: 480)
    }
}
