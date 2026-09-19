// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Phase 0 UI spike. One window shaped like Mila's main window, exercising the
// hard parts of the port's UI checklist on SwiftCrossUI 0.9.0.

import DefaultBackend
import Foundation
import SwiftCrossUI

struct Segment: Identifiable, Equatable {
    let id = UUID()
    let start: String
    let speaker: String
    let text: String
}

struct Recording: Identifiable, Equatable {
    let id = UUID()
    var title: String
    let language: String
    let segments: [Segment]
}

let sampleRecordings: [Recording] = [
    Recording(title: "פגישת צוות שבועית", language: "he", segments: [
        Segment(start: "00:00", speaker: "דנה", text: "שלום לכולם, נתחיל בסקירה של השבוע שעבר."),
        Segment(start: "00:07", speaker: "יואב", text: "העברנו את סביבת ה-staging לחשבון החדש ביום שישי."),
        Segment(start: "00:15", speaker: "דנה", text: "מצוין. מה לגבי ה-pull request של מודול ההקלטה?"),
    ]),
    Recording(title: "Weekly sync", language: "en", segments: [
        Segment(start: "00:00", speaker: "Dana", text: "We agreed to migrate the staging environment by Friday."),
        Segment(start: "00:06", speaker: "Yoav", text: "The team will open a pull request today."),
    ]),
]

@main
struct UISpikeApp: App {
    var body: some Scene {
        WindowGroup("OpenMila UI spike") {
            RootView()
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            CommandMenu("Recording") {
                Button("New Recording") { print("menu: new recording") }
                Button("Export SRT") { print("menu: export srt") }
            }
        }
    }
}

struct RootView: View {
    @State var recordings = sampleRecordings
    @State var selection: UUID?
    @State var dark = false
    @State var showSettings = false
    @State var showRename = false
    @State var renameDraft = ""

    var selected: Recording? { recordings.first { $0.id == selection } }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                Text("All Transcriptions").font(.headline).padding()
                ScrollView {
                    List(recordings, selection: $selection) { recording in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recording.title).font(.callout)
                            Text("\(recording.segments.count) segments, \(recording.language)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                Divider()
                HStack {
                    Button("Settings") { showSettings = true }
                    Toggle("Dark", isOn: $dark)
                }.padding()
            }
            .frame(minWidth: 230)
        } detail: {
            if let recording = selected {
                DetailView(recording: recording) {
                    renameDraft = recording.title
                    showRename = true
                }
            } else {
                Text("Select a recording").foregroundColor(.gray)
            }
        }
        .preferredColorScheme(dark ? .dark : .light)
        .sheet(isPresented: $showSettings) { SettingsSheet(isPresented: $showSettings) }
        .sheet(isPresented: $showRename) {
            VStack(alignment: .leading) {
                Text("Rename recording").font(.title3)
                TextField("Title", text: $renameDraft)
                HStack {
                    Button("Cancel") { showRename = false }
                    Button("Save") {
                        if let index = recordings.firstIndex(where: { $0.id == selection }) {
                            recordings[index].title = renameDraft
                        }
                        showRename = false
                    }
                }
            }.padding().frame(minWidth: 360)
        }
    }
}

struct DetailView: View {
    let recording: Recording
    let onRename: () -> Void
    @State var speed: Double? = 1.0
    @State var playing = false
    @State var notes = ""
    @State var position = 0.3

    var isRTL: Bool { recording.language == "he" }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(recording.title).font(.title2)
                Spacer()
                Menu("Actions") {
                    Button("Rename") { onRename() }
                    Button("Regenerate summary") { print("action: regenerate") }
                    Button("Copy transcript") { print("action: copy") }
                    Button("Move to Trash") { print("action: trash") }
                }
            }
            // Playback bar with a speed menu, as in Mila 1.9.5.
            HStack {
                Button(playing ? "Pause" : "Play") { playing.toggle() }
                Slider(value: $position, in: 0...1)
                Picker(of: [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], selection: $speed)
            }
            Divider()
            ScrollView {
                VStack(alignment: isRTL ? .trailing : .leading, spacing: 10) {
                    ForEach(recording.segments) { segment in
                        VStack(alignment: isRTL ? .trailing : .leading, spacing: 2) {
                            Text("\(segment.speaker)  \(segment.start)")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text(segment.text)
                                .font(.body)
                                .multilineTextAlignment(isRTL ? .trailing : .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                    }
                }.padding()
            }
            Divider()
            Text("Context for Live AI").font(.caption)
            TextEditor(text: $notes).frame(minHeight: 80)
        }
        .padding()
    }
}

struct SettingsSheet: View {
    @Binding var isPresented: Bool
    @State var section: String? = "General"
    @State var betaUpdates = false
    @State var adaptiveGain = true
    @State var language: String? = "Hebrew"
    @State var throttle = 20.0
    @State var endpoint = "https://api.openai.com/v1"

    let sections = ["General", "Audio", "Models", "AI Provider", "AI Features",
                    "Speakers", "Meetings", "Watched Folders", "Storage"]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Settings").font(.title3)
            HStack(alignment: .top) {
                List(sections, id: \.self, selection: $section) { Text($0) }
                    .frame(minWidth: 160)
                VStack(alignment: .leading, spacing: 12) {
                    Text(section ?? "").font(.headline)
                    Toggle("Receive beta versions", isOn: $betaUpdates)
                    Toggle("Adaptive gain for quiet microphones", isOn: $adaptiveGain)
                    HStack { Text("Recording language"); Picker(of: ["Hebrew", "English"], selection: $language) }
                    Text("Live AI interval: \(Int(throttle)) s").font(.callout)
                    Slider(value: $throttle, in: 5...60)
                    TextField("Transcription endpoint", text: $endpoint)
                }.padding()
            }
            HStack { Spacer(); Button("Done") { isPresented = false } }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 420)
    }
}
