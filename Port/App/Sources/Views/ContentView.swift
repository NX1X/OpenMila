// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port of `Mila/Views/ContentView.swift`: the three-column window.

import Foundation
import SwiftCrossUI
@testable import Mila

enum SidebarSection: Hashable {
    case home
    case all
    case folder(String)
    case dictations
    case trash

    var title: String {
        switch self {
        case .home: return "Home"
        case .all: return "All Transcriptions"
        case .folder(let name): return name
        case .dictations: return "Dictations"
        case .trash: return "Recently Deleted"
        }
    }
}

struct ContentView: View {
    let model: AppModel
    @State var store: Observed<RecordingStore>
    @State var transcription: Observed<TranscriptionService>
    @State var section: SidebarSection? = .home
    @State var selectedRecording: UUID?
    @State var showSettings = false

    init(model: AppModel) {
        self.model = model
        _store = State(wrappedValue: Observed(model.store))
        _transcription = State(wrappedValue: Observed(model.transcription))
    }

    var visibleRecordings: [Recording] {
        let all = store.object.recordings
        switch section {
        case .trash: return all.filter { $0.deletedAt != nil }
        case .folder(let name): return all.filter { $0.deletedAt == nil && $0.folder == name }
        case .dictations: return all.filter { $0.deletedAt == nil && $0.title.hasPrefix("Dictation") }
        default: return all.filter { $0.deletedAt == nil }
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, section: $section, showSettings: $showSettings)
                .frame(minWidth: Theme.sidebarMinWidth)
        } content: {
            if section == .home {
                HomeView(model: model, transcription: transcription)
            } else {
                HistoryListView(recordings: visibleRecordings, transcription: transcription,
                                selection: $selectedRecording, title: section?.title ?? "")
            }
        } detail: {
            if let id = selectedRecording, let recording = store.object.recordings.first(where: { $0.id == id }) {
                RecordingDetailView(model: model, store: store, recording: recording)
            } else if section != .home {
                Text("Select a recording").foregroundColor(Theme.secondaryText).padding()
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model, isPresented: $showSettings)
        }
    }
}

struct SidebarView: View {
    let store: Observed<RecordingStore>
    @Binding var section: SidebarSection?
    @Binding var showSettings: Bool
    @State var showFolderSheet = false
    @State var folderDraft = ""
    @State var renamingFolder: String?
    @State var trashNotice = ""

    var sections: [SidebarSection] {
        [.home, .all] + store.object.folders.map { .folder($0) } + [.dictations, .trash]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppIdentity.name).font(.headline).padding()
            List(sections, id: \.self, selection: $section) { item in
                Text(item.title).font(.callout)
            }
            Spacer()
            Menu("Folders") {
                Button("New folder...") { renamingFolder = nil; folderDraft = ""; showFolderSheet = true }
                if case .folder(let name) = section {
                    Button("Rename \"\(name)\"...") { renamingFolder = name; folderDraft = name; showFolderSheet = true }
                    Button("Delete \"\(name)\"") { store.object.deleteFolder(name); section = .all }
                }
                if section == .trash {
                    Button("Empty Trash") {
                        let n = store.object.emptyTrash()
                        trashNotice = "Deleted \(n) recording\(n == 1 ? "" : "s")."
                    }
                }
            }.padding([.leading, .trailing])
            if !trashNotice.isEmpty { Text(trashNotice).font(.caption).padding([.leading, .trailing]) }
            Divider()
            HStack {
                Button("Settings") { showSettings = true }
                Spacer()
                Text(AppIdentity.version).font(.caption2).foregroundColor(Theme.secondaryText)
            }.padding()
        }
        .sheet(isPresented: $showFolderSheet) {
            VStack(alignment: .leading, spacing: 10) {
                Text(renamingFolder == nil ? "New folder" : "Rename folder").font(.title3)
                TextField("Folder name", text: $folderDraft)
                HStack {
                    Button("Cancel") { showFolderSheet = false }
                    Button("Save") {
                        if let old = renamingFolder {
                            if let renamed = store.object.renameFolder(old, to: folderDraft) { section = .folder(renamed) }
                        } else if let created = store.object.createFolder(folderDraft) {
                            section = .folder(created)
                        }
                        showFolderSheet = false
                    }
                }
            }.padding().frame(minWidth: 380)
        }
    }
}

struct HistoryListView: View {
    let recordings: [Recording]
    let transcription: Observed<TranscriptionService>
    @Binding var selection: UUID?
    let title: String

    func status(_ recording: Recording) -> String {
        if transcription.object.activeRecordingID == recording.id {
            return "Transcribing \(Int(transcription.object.progress * 100))%"
        }
        if transcription.object.pendingIDs.contains(recording.id) { return "Queued" }
        switch recording.status {
        case .pending: return "Pending"
        case .running: return "Transcribing"
        case .completed: return String(format: "%d:%02d", Int(recording.duration) / 60, Int(recording.duration) % 60)
        case .failed: return "Failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.title3).padding()
            if recordings.isEmpty {
                Text("No recordings yet").foregroundColor(Theme.secondaryText).padding()
            }
            ScrollView {
                List(recordings, selection: $selection) { recording in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.title).font(.callout)
                        Text("\(Self.dateText(recording.createdAt))  \(status(recording))")
                            .font(.caption).foregroundColor(Theme.secondaryText)
                    }
                }
            }
        }
    }

    static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
