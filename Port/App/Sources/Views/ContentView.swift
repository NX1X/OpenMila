// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port of `Mila/Views/ContentView.swift`: the three-column window.

import Foundation
import SwiftCrossUI
@testable import Mila

enum SidebarSection: Hashable {
    /// Where the window opens. Home, unless OPENMILA_START_SECTION names
    /// another section: that exists for the Windows CI capture, which starts
    /// the app on the recordings list to photograph the three-column layout
    /// rather than driving a WinUI list blind by keyboard.
    static var startingSection: SidebarSection? {
        switch ProcessInfo.processInfo.environment["OPENMILA_START_SECTION"] {
        case "all": return .all
        case "dictations": return .dictations
        case "trash": return .trash
        default: return .home
        }
    }

    case home
    case all
    case folder(String)
    case dictations
    case trash

    var folderName: String? {
        if case .folder(let name) = self { return name }
        return nil
    }

    /// Upstream's SF Symbols mapped to freedesktop icon names (see Icons.swift).
    var icon: String {
        switch self {
        case .home: return AppIcon.home
        case .all: return AppIcon.list
        case .folder: return AppIcon.folder
        case .dictations: return AppIcon.dictation
        case .trash: return AppIcon.trash
        }
    }

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
    @State var section: SidebarSection? = SidebarSection.startingSection
    @State var selectedRecording: UUID?
    @State var showSettings = false
    @State var importer: Observed<MilaConfigImporter>
    @State var whatsNew: WhatsNewUpdate?
    @State var showWhatsNew = false
    @State var ui: Observed<UIRequests>

    init(model: AppModel) {
        self.model = model
        _store = State(wrappedValue: Observed(model.store))
        _transcription = State(wrappedValue: Observed(model.transcription))
        _importer = State(wrappedValue: Observed(model.configImporter))
        _ui = State(wrappedValue: Observed(model.ui))
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

    /// Two layouts, not one with an empty slot. `NavigationSplitView` is two
    /// nested split panes, and on WinUI a pane is fixed at its minimum width,
    /// so a three-column layout whose detail is empty (Home) drew the page in
    /// a narrow middle column and left the wide pane blank: "a third of the
    /// window and a black box", in the first hands-on report. GTK lets the
    /// user drag the divider, which is why Linux never showed it. Home is a
    /// page, so it takes the wide slot; the recordings sections are a list
    /// beside a detail, which is what the three columns are for.
    @ViewBuilder var split: some View {
        if section == .home {
            NavigationSplitView {
                sidebar
            } detail: {
                HomeView(model: model, transcription: transcription)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            NavigationSplitView {
                sidebar
            } content: {
                HistoryListView(model: model, recordings: visibleRecordings, transcription: transcription,
                                selection: $selectedRecording, title: section?.title ?? "")
                    .frame(minWidth: Theme.listMinWidth)
            } detail: {
                if let id = selectedRecording, let recording = store.object.recordings.first(where: { $0.id == id }) {
                    RecordingDetailView(model: model, store: store, recording: recording)
                } else {
                    Text("Select a recording").foregroundColor(Theme.secondaryText).padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    var sidebar: some View {
        SidebarView(store: store, section: $section, showSettings: $showSettings, ui: ui)
            .frame(minWidth: Theme.sidebarMinWidth)
    }

    var body: some View {
        split
        // The window's minimum size comes from its content, so without this the
        // user can drag the window down to a width where a label wraps to one
        // word - or one character - per line, which is what the download
        // banner looked like when it was reported. Upstream fixes the same
        // number on the macOS window (min width 1000).
        .frame(minWidth: Theme.windowMinWidth, minHeight: Theme.windowMinHeight)
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model, isPresented: $showSettings)
        }
        .sheet(isPresented: Binding(get: { importer.object.pending != nil }, set: { if !$0 { model.configImporter.cancel() } })) {
            MilaConfigConfirmationView(importer: importer)
        }
        .sheet(isPresented: Binding(get: { ui.object.showAbout }, set: { ui.object.showAbout = $0 })) {
            AboutView(isPresented: Binding(get: { ui.object.showAbout }, set: { ui.object.showAbout = $0 }),
                      markURL: model.platform.paths.resource(named: AppBranding.markFileName))
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewPopup(update: whatsNew, onUpdate: {
                if let v = whatsNew?.displayVersion { model.whatsNewGate.markSeen(version: v) }
                showWhatsNew = false
            }, onLater: {
                if let v = whatsNew?.displayVersion { model.whatsNewGate.markSeen(version: v) }
                showWhatsNew = false
            })
        }
        .task {
            if let update = await model.checkForWhatsNew() {
                whatsNew = update
                showWhatsNew = true
            }
        }
        .platformWindowIcon(named: AppBranding.iconName, searchPaths: AppBranding.iconSearchPaths)
    }
}

/// Port of `Mila/Views/MilaConfigConfirmationView.swift`.
struct MilaConfigConfirmationView: View {
    let importer: Observed<MilaConfigImporter>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pending = importer.object.pending {
                Text("Apply \(pending.sourceName)?").font(.title3)
                Text("These settings will change. Anything not listed stays as it is.").font(.caption).foregroundColor(Theme.secondaryText)
                ForEach(pending.changes) { change in
                    HStack { Text(change.label).font(.callout); Spacer(); Text(change.value).font(.callout).foregroundColor(Theme.secondaryText) }
                }
                HStack {
                    Button("Cancel") { importer.object.cancel() }
                    Button("Apply") { importer.object.confirm() }
                }
            }
            if let error = importer.object.errorMessage { Text(error).foregroundColor(Theme.danger).font(.callout) }
        }.padding().frame(minWidth: 460)
    }
}

/// Port of `Mila/Views/WhatsNewPopup.swift`: highlights of the newer version
/// found by the scheduled check, with Update (opens the release page) or Later.
struct WhatsNewPopup: View {
    let update: WhatsNewUpdate?
    let onUpdate: () -> Void
    let onLater: () -> Void
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's New in \(AppIdentity.name) \(update?.displayVersion ?? "")").font(.title3)
            ForEach(update?.highlights ?? [], id: \.self) { line in
                Text("- \(line)").font(.callout)
            }
            HStack {
                Button("Later") { onLater() }
                Button("Open release page") {
                    if let url = URL(string: "https://github.com/\(AppIdentity.repository)/releases/latest") { openURL(url) }
                    onUpdate()
                }
            }
        }.padding().frame(minWidth: 480)
    }
}

struct SidebarView: View {
    let store: Observed<RecordingStore>
    @Binding var section: SidebarSection?
    @Binding var showSettings: Bool
    let ui: Observed<UIRequests>
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
                HStack(spacing: 8) {
                    PlatformIcon(item.icon)
                    Text(item.title).font(.callout)
                }
                .platformDropTarget(enabled: item.folderName != nil) { id in
                    guard let name = item.folderName,
                          var recording = store.object.recordings.first(where: { $0.id == id }) else { return }
                    recording.folder = name
                    _ = store.object.update(recording)
                }
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
                // Natural width: in a narrow sidebar the row's space was split
                // evenly and the labels wrapped to "Setting / s".
                Button("Settings") { showSettings = true }.fixedSize(horizontal: true, vertical: false)
                Button("About") { ui.object.showAbout = true }.fixedSize(horizontal: true, vertical: false)
                Spacer()
                // The version on its own line under the buttons, not fighting
                // them for the row: beside them it wrapped to "1.9.5-/beta.2+po/rt.5".
            }.padding([.leading, .trailing, .top])
            Text(AppIdentity.version).font(.caption2).foregroundColor(Theme.secondaryText)
                .padding([.leading, .trailing, .bottom])
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
    let model: AppModel
    let recordings: [Recording]
    let transcription: Observed<TranscriptionService>
    @Binding var selection: UUID?
    let title: String

    /// Upstream: RecordingContextMenu.
    func rowActions(_ recording: Recording) -> [ContextMenuItem] {
        let store = model.store
        if recording.deletedAt != nil {
            return [
                ContextMenuItem("Restore") { store.restore(recording) },
                ContextMenuItem("Delete permanently", destructive: true) { store.permanentlyDelete(recording) },
            ]
        }
        var items: [ContextMenuItem] = [
            ContextMenuItem("Open") { selection = recording.id },
            ContextMenuItem("Re-transcribe") { model.transcription.enqueue(recording, isRetranscription: true) },
            ContextMenuItem("Regenerate summary") { model.summarizer.regenerate(recording) },
        ]
        if recording.folder != nil {
            items.append(ContextMenuItem("Remove from folder") {
                var updated = recording; updated.folder = nil; _ = store.update(updated)
            })
        }
        for folder in store.folders where folder != recording.folder {
            items.append(ContextMenuItem("Move to \(folder)") {
                var updated = recording; updated.folder = folder; _ = store.update(updated)
            })
        }
        items.append(ContextMenuItem("Move to Trash", destructive: true) { store.delete(recording) })
        return items
    }

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
                    .platformContextMenu(rowActions(recording))
                    .platformDragSource(recording.id)
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
