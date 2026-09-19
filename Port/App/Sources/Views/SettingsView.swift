// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port of `Mila/Views/SettingsView.swift`: a section sidebar with the same
// sections in the same order. Voice Memos becomes Watched Folders.

import Foundation
import PlatformKit
import SwiftCrossUI
import Updater
@testable import Mila

struct SettingsView: View {
    let model: AppModel
    @Binding var isPresented: Bool
    @State var section: String? = "General"
    @State var models: Observed<ModelManager>
    @State var remote: Observed<RemoteTranscriptionSettings>
    @State var llm: Observed<LLMSettings>
    @State var storage: Observed<RecordingStorageSettings>
    @State var mcp: Observed<MCPAccessSettings>
    @State var audio: Observed<AudioInputSettings>
    @State var betaUpdates = UserDefaults.standard.bool(forKey: "updates.betaChannel")
    @State var updateStatus = ""
    @State var devices: [AudioInputDevice] = []
    @State var deviceName: String? = "System default"
    @State var storageGB = 0.0

    static let sections = ["General", "Audio", "Models", "AI Provider", "AI Features",
                           "Speakers", "Meetings", "Watched Folders", "Storage"]

    init(model: AppModel, isPresented: Binding<Bool>) {
        self.model = model
        _isPresented = isPresented
        _models = State(wrappedValue: Observed(model.modelManager))
        _remote = State(wrappedValue: Observed(model.remoteSettings))
        _llm = State(wrappedValue: Observed(model.llmSettings))
        _storage = State(wrappedValue: Observed(model.storageSettings))
        _mcp = State(wrappedValue: Observed(model.mcpAccess))
        _audio = State(wrappedValue: Observed(model.audioInput))
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Settings").font(.title3)
            HStack(alignment: .top, spacing: 12) {
                List(Self.sections, id: \.self, selection: $section) { Text($0) }
                    .frame(minWidth: 170)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch section {
                        case "General": general
                        case "Audio": audioSection
                        case "Models": modelsSection
                        case "AI Provider": aiProvider
                        case "AI Features": aiFeatures
                        case "Storage": storageSection
                        case "Watched Folders": Text("Watched folders arrive with the importer port.").font(.callout)
                        default: Text("Coming with the next views.").font(.callout).foregroundColor(Theme.secondaryText)
                        }
                    }.padding()
                }
            }
            HStack { Spacer(); Button("Done") { isPresented = false } }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 480)
        .onAppear {
            devices = (try? model.platform.microphone.inputDevices()) ?? []
            if let id = model.audioInput.preferredUID, let d = devices.first(where: { $0.id == id }) { deviceName = d.name }
            storageGB = model.storageSettings.limitGigabytes
        }
    }

    var general: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("General").font(.headline)
            Toggle("Receive beta versions", isOn: $betaUpdates)
                .onChange(of: betaUpdates) { UserDefaults.standard.set(betaUpdates, forKey: "updates.betaChannel") }
            HStack {
                Button("Check for updates") {
                    updateStatus = "Checking..."
                    Task {
                        do {
                            if let u = try await model.platform.updater?.check(includePrereleases: betaUpdates) {
                                updateStatus = "Version \(u.version) is available: \(u.downloadPage)"
                            } else { updateStatus = "You are up to date." }
                        } catch { updateStatus = "Check failed: \(error.localizedDescription)" }
                    }
                }
                Text(updateStatus).font(.caption)
            }
            Divider()
            Text("Dictation hotkeys").font(.headline)
            Text("Global shortcuts need an X11 session or a desktop that supports the GlobalShortcuts portal. Configuration arrives with the dictation port.")
                .font(.caption).foregroundColor(Theme.secondaryText)
            Divider()
            Text("Logs: \(model.platform.paths.logDirectory.path)").font(.caption)
        }
    }

    var audioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio").font(.headline)
            HStack {
                Text("Input device").font(.callout)
                Picker(of: ["System default"] + devices.map(\.name), selection: $deviceName)
                    .onChange(of: deviceName) {
                        model.audioInput.preferredUID = devices.first { $0.name == deviceName }?.id
                    }
            }
            Toggle("Adaptive gain for quiet microphones", isOn: Binding(
                get: { audio.object.adaptiveGainEnabled },
                set: { audio.object.adaptiveGainEnabled = $0 }))
        }
    }

    var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Models").font(.headline)
            ForEach(WhisperModel.all, id: \.name) { m in
                HStack {
                    Text(m.displayName).font(.callout)
                    if let progress = models.object.downloads[m.name] {
                        Text("Downloading \(Int(progress * 100))%").font(.caption)
                    } else if models.object.installed.contains(m.name) {
                        Text("Installed").font(.caption).foregroundColor(Theme.success)
                        Button(models.object.selectedModelName == m.name ? "Selected" : "Select") { models.object.setSelected(m) }
                        Button("Delete") { try? models.object.delete(m) }
                    } else {
                        Button("Download") { models.object.download(m) }
                    }
                    if let err = models.object.lastDownloadErrors[m.name] { Text(err).font(.caption).foregroundColor(Theme.danger) }
                }
            }
            Divider()
            Text("Backend").font(.headline)
            Picker(of: TranscriptionBackend.allCases.map(\.rawValue), selection: Binding(
                get: { remote.object.backend.rawValue },
                set: { if let v = $0, let b = TranscriptionBackend(rawValue: v) { remote.object.backend = b } }))
            if remote.object.backend != .local {
                TextField("Endpoint (https://.../v1)", text: Binding(get: { remote.object.endpoint }, set: { remote.object.endpoint = $0 }))
                TextField("Model", text: Binding(get: { remote.object.model }, set: { remote.object.model = $0 }))
                TextField("English model (optional)", text: Binding(get: { remote.object.englishModel }, set: { remote.object.englishModel = $0 }))
                SecureField("API key", text: Binding(get: { remote.object.apiKey }, set: { remote.object.apiKey = $0 }))
                HStack {
                    Button("Test connection") { Task { await remote.object.testConnection() } }
                    Text(String(describing: remote.object.testStatus)).font(.caption)
                }
                Text("Audio leaves this machine while a remote backend is active.").font(.caption).foregroundColor(Theme.danger)
            }
        }
    }

    var aiProvider: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Provider").font(.headline)
            Picker(of: LLMTool.allCases.map(\.rawValue), selection: Binding(
                get: { llm.object.tool.rawValue },
                set: { if let v = $0, let t = LLMTool(rawValue: v) { llm.object.tool = t } }))
            TextField("Executable path (optional)", text: Binding(get: { llm.object.executablePath }, set: { llm.object.executablePath = $0 }))
            TextField("OpenAI-compatible base URL", text: Binding(get: { llm.object.openAIBaseURL }, set: { llm.object.openAIBaseURL = $0 }))
            TextField("Model name", text: Binding(get: { llm.object.openAIModelName }, set: { llm.object.openAIModelName = $0 }))
            SecureField("API key", text: Binding(get: { llm.object.openAIAPIKey }, set: { llm.object.openAIAPIKey = $0 }))
        }
    }

    var aiFeatures: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Features").font(.headline)
            Toggle("Suggest recording names", isOn: Binding(get: { llm.object.nameGenerationEnabled }, set: { llm.object.nameGenerationEnabled = $0 }))
            Toggle("Automatic summary after each recording", isOn: Binding(get: { llm.object.summaryEnabled }, set: { llm.object.summaryEnabled = $0 }))
            Text("Summary prompt").font(.callout)
            TextEditor(text: Binding(get: { llm.object.postActionPrompt }, set: { llm.object.postActionPrompt = $0 })).frame(minHeight: 100)
        }
    }

    var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage").font(.headline)
            Text("Recordings: \(model.store.recordingsDirectory.path)").font(.caption)
            Text("Storage cap: \(Int(storageGB)) GB").font(.callout)
            Slider(value: $storageGB, in: 1...200)
                .onChange(of: storageGB) { storage.object.limitBytes = Int64(storageGB * 1_073_741_824) }
            Divider()
            Toggle("Allow MCP access to transcriptions", isOn: Binding(get: { mcp.object.enabled }, set: { mcp.object.enabled = $0 }))
            Text("Off by default. Lets tools like Claude Code read your transcripts through the openmila-mcp helper.").font(.caption).foregroundColor(Theme.secondaryText)
        }
    }
}
