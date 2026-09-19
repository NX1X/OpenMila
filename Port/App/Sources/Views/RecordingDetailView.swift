// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port of `Mila/Views/RecordingDetailView.swift`: playback with speed,
// transcript with speaker colours and per-block direction, rename, export,
// trash.

import AudioCapture
import Foundation
import SwiftCrossUI
import MilaKit
import TranscriptionCore
@testable import Mila

struct RecordingDetailView: View {
    let model: AppModel
    let store: Observed<RecordingStore>
    let recording: Recording
    @State var player: PlayerBox = PlayerBox()
    @State var speed: Double? = 1.0
    @State var showRename = false
    @State var draftTitle = ""
    @State var tick = 0
    @State var notice: String?
    @State var showSpeakerSheet = false
    @State var speakerToName = ""
    @State var speakerDraft = ""
    @State var showNewFolder = false
    @State var newFolderName = ""

    final class PlayerBox {
        var player: MiniaudioPlayer?
        var url: URL?
    }

    var isTrashed: Bool { recording.deletedAt != nil }

    func ensurePlayer() -> MiniaudioPlayer? {
        let url = model.store.audioURL(for: recording)
        if player.url != url {
            player.player = try? MiniaudioPlayer(url: url)
            player.url = url
        }
        return player.player
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(recording.title).font(.title2)
                Spacer()
                Menu("Actions") {
                    Button("Rename") { draftTitle = recording.title; showRename = true }
                    Button("Copy transcript") {
                        _ = model.platform.textInjector.map { _ in }
                        let text = TranscriptFormatter.plainText(segments: recording.segments,
                                                                 fallback: recording.fullText,
                                                                 names: [:])
                        Task { _ = await LinuxClipboard.copy(text) ; notice = "Transcript copied." }
                    }
                    Button("Export SRT") {
                        let url = model.platform.paths.dataDirectory.appendingPathComponent("\(recording.title).srt")
                        do { try TranscriptExporter.writeSRT(for: recording, to: url); notice = "Saved \(url.path)" }
                        catch { notice = error.localizedDescription }
                    }
                    Button("Re-transcribe") { model.transcription.enqueue(recording, isRetranscription: true) }
                    Button("Regenerate summary") { model.summarizer.regenerate(recording) }
                    Menu("Move to folder") {
                        Button("No folder") { moveTo(nil) }
                        ForEach(model.store.folders, id: \.self) { name in
                            Button(name) { moveTo(name) }
                        }
                        Button("New folder...") { newFolderName = ""; showNewFolder = true }
                    }
                    if isTrashed {
                        Button("Restore") { model.store.restore(recording) }
                        Button("Delete permanently") { model.store.permanentlyDelete(recording) }
                    } else {
                        Button("Move to Trash") { model.store.delete(recording) }
                    }
                }
            }
            Text("\(HistoryListView.dateText(recording.createdAt))  \(recording.language.uppercased())  \(recording.status.rawValue)")
                .font(.caption).foregroundColor(Theme.secondaryText)
            if let notice { Text(notice).font(.caption).foregroundColor(Theme.accent) }

            HStack(spacing: 10) {
                Button(player.player?.isPlaying == true ? "Pause" : "Play") {
                    guard let p = ensurePlayer() else { return }
                    if p.isPlaying { p.pause() } else { p.play() }
                    tick += 1
                }
                Text(Self.clock(player.player?.position ?? 0) + " / " + Self.clock(recording.duration)).font(.callout)
                Picker(of: [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], selection: $speed)
                    .onChange(of: speed) { if let speed { player.player?.setRate(speed) } }
            }
            Divider()
            if let summary = recording.summary, !summary.isEmpty {
                Text("Summary").font(.headline)
                Text(summary).font(.body).multilineTextAlignment(summary.isRTLText ? .trailing : .leading)
                if let items = recording.actionItems, !items.isEmpty {
                    Text("Action items").font(.headline)
                    ForEach(items) { Text("- \($0.text)").font(.callout) }
                }
                Divider()
            } else if model.summarizer.isSummarizing(recording.id) {
                Text("Summarising...").font(.caption).foregroundColor(Theme.secondaryText)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if recording.segments.isEmpty {
                        Text(recording.fullText.isEmpty ? "No transcript yet." : recording.fullText)
                            .font(.body)
                    }
                    ForEach(recording.segments) { segment in
                        VStack(alignment: segment.text.isRTLText ? .trailing : .leading, spacing: 2) {
                            HStack {
                                if let speaker = segment.speaker {
                                    Button(recording.speakerNames[speaker] ?? speaker) {
                                        speakerToName = speaker
                                        speakerDraft = recording.speakerNames[speaker] ?? ""
                                        showSpeakerSheet = true
                                    }
                                    .foregroundColor(Theme.speakerColor(speaker))
                                }
                                Text(Self.clock(segment.start)).font(.caption).foregroundColor(Theme.secondaryText)
                            }
                            Text(segment.text)
                                .font(.body)
                                .multilineTextAlignment(segment.text.isRTLText ? .trailing : .leading)
                                .onTapGesture { ensurePlayer()?.seek(to: segment.start); tick += 1 }
                        }
                        .frame(maxWidth: .infinity, alignment: segment.text.isRTLText ? .trailing : .leading)
                    }
                }.padding()
            }
        }
        .padding()
        .sheet(isPresented: $showRename) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rename recording").font(.title3)
                TextField("Title", text: $draftTitle)
                HStack {
                    Button("Cancel") { showRename = false }
                    Button("Save") { model.store.rename(recording, to: draftTitle); showRename = false }
                }
            }.padding().frame(minWidth: 380)
        }
        .sheet(isPresented: $showSpeakerSheet) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Name speaker \(speakerToName)").font(.title3)
                TextField("Name", text: $speakerDraft)
                let suggestions = model.speakerDirectory.matches(for: speakerDraft).prefix(6)
                if !suggestions.isEmpty {
                    HStack {
                        ForEach(Array(suggestions), id: \.self) { name in
                            Button(name) { speakerDraft = name }
                        }
                    }
                }
                HStack {
                    Button("Cancel") { showSpeakerSheet = false }
                    Button("Un-name") { applySpeakerName(nil); showSpeakerSheet = false }
                    Button("Save") { applySpeakerName(speakerDraft); showSpeakerSheet = false }
                }
            }.padding().frame(minWidth: 420)
        }
        .sheet(isPresented: $showNewFolder) {
            VStack(alignment: .leading, spacing: 10) {
                Text("New folder").font(.title3)
                TextField("Folder name", text: $newFolderName)
                HStack {
                    Button("Cancel") { showNewFolder = false }
                    Button("Create and move") {
                        if let created = model.store.createFolder(newFolderName) { moveTo(created) }
                        showNewFolder = false
                    }
                }
            }.padding().frame(minWidth: 380)
        }
        .task {
            while true {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if player.player?.isPlaying == true { tick += 1 }
            }
        }
    }

    func moveTo(_ folder: String?) {
        var updated = recording
        updated.folder = folder
        _ = model.store.update(updated)
        notice = folder.map { "Moved to \($0)." } ?? "Removed from folder."
    }

    /// Upstream: SpeakerNamePicker. A name is remembered in the directory
    /// and applied to every segment carrying this speaker id.
    func applySpeakerName(_ name: String?) {
        var updated = recording
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            updated.speakerNames.removeValue(forKey: speakerToName)
        } else {
            updated.speakerNames[speakerToName] = trimmed
            _ = model.speakerDirectory.add(trimmed)
        }
        _ = model.store.update(updated)
    }

    static func clock(_ seconds: Double) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

enum LinuxClipboard {
    static func copy(_ text: String) async -> Bool {
        for (name, args) in [("wl-copy", [String]()), ("xclip", ["-selection", "clipboard"])] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/\(name)")
            guard FileManager.default.isExecutableFile(atPath: process.executableURL!.path) else { continue }
            process.arguments = args
            let pipe = Pipe()
            process.standardInput = pipe
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { continue }
            pipe.fileHandleForWriting.write(Data(text.utf8))
            try? pipe.fileHandleForWriting.close()
            return true
        }
        return false
    }
}
