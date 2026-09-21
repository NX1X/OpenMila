// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port of `Mila/Views/SettingsView.swift`: a section sidebar with the same
// sections in the same order. Voice Memos becomes Watched Folders.

import Dictation
import Foundation
import LocalAI
#if os(Linux)
import LinuxPlatform
#endif
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
    @State var directory: Observed<SpeakerDirectory>
    @State var voice: Observed<VoiceRecognitionSettings>
    @State var meetings: Observed<MeetingDetectionSettings>
    @State var watched: Observed<VoiceMemosSettings>
    @State var watchedPath = ""
    @State var watchedError: String?
    @State var gpuEnabled = true
    @State var gpuDevice = GPUSettings.automaticLabel
    @State var aiProviderStatus = ""
    @State var localModelTitle = LocalModel.recommended.title
    @State var localAIStatus = ""
    @State var localAIBusy = false
    @State var hotkeys: Observed<HotkeySettings>
    @State var chordEN = ""
    @State var chordHE = ""
    @State var chordNotice = ""
    @State var diagnosticsNotice = ""
    @Environment(\.chooseFile) var chooseFile
    @State var betaUpdates = UserDefaults.standard.bool(forKey: "updates.betaChannel")
    @State var updateStatus = ""
    /// The update a check found, so the Install button knows what to fetch.
    @State var pendingUpdate: AvailableUpdate?
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
        _directory = State(wrappedValue: Observed(model.speakerDirectory))
        _voice = State(wrappedValue: Observed(model.voiceRecognition))
        _meetings = State(wrappedValue: Observed(model.meetingDetection))
        _watched = State(wrappedValue: Observed(model.watchedFolders))
        _hotkeys = State(wrappedValue: Observed(model.hotkeys))
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
                        case "Speakers": speakersSection
                        case "Meetings": meetingsSection
                        case "Watched Folders": watchedSection
                        default: EmptyView()
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
            // Never leave this empty: a blank field invites a path typed by
            // hand, and the shortest thing to type is the home directory,
            // which would make every folder in it import material.
            watchedPath = model.watchedFolders.grantedFolderURL?.path
                ?? VoiceMemosSettings.suggestedFolder.path
            chordEN = model.hotkeys.chord(for: .english).displayName
            chordHE = model.hotkeys.chord(for: .hebrew).displayName
            gpuEnabled = model.gpu.isEnabled
            gpuDevice = model.gpu.selectedLabel
        }
    }

    var speakersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Speakers").font(.headline)
            Toggle("Recognise the same speaker across recordings", isOn: Binding(
                get: { voice.object.isEnabled }, set: { voice.object.isEnabled = $0 }))
            Text("Off by default. When on, a named voice is labelled automatically in later recordings.")
                .font(.caption).foregroundColor(Theme.secondaryText)
            Button("Delete everything learned about voices") { model.speakerProfiles.deleteAllProfiles() }
            Divider()
            Text("Speaker directory").font(.headline)
            if directory.object.names.isEmpty {
                Text("Names you give speakers are remembered here.").font(.caption).foregroundColor(Theme.secondaryText)
            }
            ForEach(directory.object.names, id: \.self) { name in
                HStack {
                    Text(name).font(.callout)
                    Button("Remove") { directory.object.remove(name) }
                }
            }
        }
    }

    var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meetings").font(.headline)
            Toggle("Offer to record when a meeting app starts", isOn: Binding(
                get: { meetings.object.enabled }, set: { meetings.object.enabled = $0 }))
            Text("Zoom and Microsoft Teams are found by their process, on any session. A meeting in a browser tab - Google Meet, Proton Meet - is found by the window title.")
                .font(.caption).foregroundColor(Theme.secondaryText)
            #if os(Linux)
            Text(LinuxMeetingSignals.titleSourceDescription)
                .font(.caption).foregroundColor(Theme.secondaryText)
            #endif
        }
    }

    var watchedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Watched Folders").font(.headline)
            Text("Mila watches the folder iCloud syncs Voice Memos into. OpenMila watches any folder you sync recordings into (Syncthing, Nextcloud, a phone mount) and imports new audio files automatically.")
                .font(.caption).foregroundColor(Theme.secondaryText)
            Toggle("Import from the watched folder", isOn: Binding(
                get: { watched.object.isEnabled }, set: { watched.object.isEnabled = $0 }))
            HStack {
                TextField("Folder path", text: $watchedPath)
                Button("Use folder") { useWatchedFolder() }
            }
            Text("Suggested: \(VoiceMemosSettings.suggestedFolder.path). OpenMila creates it if it does not exist. Pick one folder for recordings, not your home directory - every folder inside the one you choose becomes an import source.")
                .font(.caption).foregroundColor(Theme.secondaryText)
            if let error = watchedError {
                Text(error).font(.caption).foregroundColor(Theme.danger)
            }
            if let granted = watched.object.grantedFolderURL {
                Text("Watching: \(granted.path)").font(.caption).foregroundColor(Theme.success)
                let library = VoiceMemosLibrary(recordingsDirectory: granted)
                Toggle("Files directly in the folder", isOn: Binding(
                    get: { watched.object.includeUnfiled }, set: { watched.object.includeUnfiled = $0 }))
                ForEach((try? library.folders()) ?? [], id: \.uuid) { sub in
                    Toggle("\(sub.name) (\(sub.count))", isOn: Binding(
                        get: { watched.object.selectedFolderUUIDs.contains(sub.uuid) },
                        set: { watched.object.setFolder(sub.uuid, selected: $0) }))
                }
                Text("Only files newer than the start date are imported, into the \"Voice Memos\" folder.")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            }
        }
    }

    /// Grants the typed folder, creating it first when it does not exist yet -
    /// the suggested path usually does not, and a button that silently fails
    /// on a folder OpenMila offered would be worse than one that makes it.
    func useWatchedFolder() {
        let path = watchedPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { watchedError = "Type a folder path first."; return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                watchedError = "Could not create \(url.path): \(error.localizedDescription)"
                return
            }
        } else if !isDirectory.boolValue {
            watchedError = "\(url.path) is a file, not a folder."
            return
        }
        watchedPath = url.path
        watchedError = model.watchedFolders.grantFolder(url) ? nil : "Could not use \(url.path)."
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
                                pendingUpdate = u
                                updateStatus = "Version \(u.version) is available: \(u.downloadPage)"
                            } else {
                                pendingUpdate = nil
                                updateStatus = "You are up to date."
                            }
                        } catch { updateStatus = "Check failed: \(error.localizedDescription)" }
                    }
                }
                if let update = pendingUpdate {
                    Button("Install \(update.version)") {
                        updateStatus = "Downloading \(update.version)..."
                        Task {
                            do {
                                switch try await model.platform.updater?.install(update) {
                                case .installed:
                                    pendingUpdate = nil
                                    updateStatus = "Version \(update.version) is installed. Quit and start OpenMila again to use it."
                                case .manual(let page):
                                    updateStatus = "This installation updates through its package: \(page)"
                                case nil:
                                    updateStatus = "No updater on this system."
                                }
                            } catch { updateStatus = "Install failed: \(error.localizedDescription)" }
                        }
                    }
                }
                Text(updateStatus).font(.caption)
            }
            Divider()
            Text("Dictation hotkeys").font(.headline)
            HStack { Text("English").font(.callout); TextField("Ctrl+Alt+2", text: $chordEN); Button("Apply") { apply(.english, chordEN) } }
            HStack { Text("Hebrew").font(.callout); TextField("Ctrl+Alt+3", text: $chordHE); Button("Apply") { apply(.hebrew, chordHE) } }
            Button("Reset to defaults") { Task { await model.hotkeys.resetToDefault(.english); await model.hotkeys.resetToDefault(.hebrew); chordEN = model.hotkeys.chord(for: .english).displayName; chordHE = model.hotkeys.chord(for: .hebrew).displayName } }
            Text(hotkeys.object.isAvailable
                 ? "Write modifiers and a key: Ctrl, Alt, Shift, Super and a letter, digit, F-key, Space, Return, Escape or Tab. \(chordNotice)"
                 : "Global shortcuts work on X11 sessions (and XWayland windows). On pure Wayland, use the Dictate buttons on Home.")
                .font(.caption).foregroundColor(Theme.secondaryText)
            Divider()
            Text("Team setup").font(.headline)
            Button("Import a .milaconfig file...") {
                Task {
                    if let url = await chooseFile(title: "Open a Mila configuration") {
                        model.configImporter.handleOpen(url)
                        isPresented = false
                    }
                }
            }
            Divider()
            Text("Diagnostics").font(.headline)
            Button("Export diagnostic report") {
                Task {
                    do { diagnosticsNotice = "Saved \((try await Diagnostics.buildReport(model: model)).path)" }
                    catch { diagnosticsNotice = error.localizedDescription }
                }
            }
            Text(diagnosticsNotice.isEmpty ? "Settings with credentials redacted, recording shapes without titles, and the log files." : diagnosticsNotice)
                .font(.caption).foregroundColor(Theme.secondaryText)
            Text("Logs: \(model.platform.paths.logDirectory.path)").font(.caption)
        }
    }

    func apply(_ language: DictationLanguage, _ text: String) {
        guard let chord = HotkeyChord.parse(text) else { chordNotice = "Could not read that combination."; return }
        Task {
            let ok = await model.hotkeys.setChord(chord, for: language)
            chordNotice = ok ? "Saved \(chord.displayName)." : "\(chord.displayName) is taken by another application."
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
            Text("Hardware").font(.headline)
            Text("This machine: \(model.gpu.summary)")
                .font(.caption).foregroundColor(Theme.secondaryText)
            if model.gpu.hasUsableDevice || !gpuEnabled {
                Toggle("Use the graphics card when one is usable", isOn: Binding(
                    get: { gpuEnabled },
                    set: { gpuEnabled = $0; model.gpu.isEnabled = $0 }))
                Text("Takes effect the next time a model is loaded. Turn it off if a driver misbehaves; transcription then runs on the processor.")
                    .font(.caption).foregroundColor(Theme.secondaryText)
                if gpuEnabled, model.gpu.devices.count > 1 {
                    Text("Which device").font(.callout)
                    Picker(of: model.gpu.deviceLabels, selection: Binding(
                        get: { gpuDevice },
                        set: { if let label = $0 { gpuDevice = label; model.gpu.choose(label: label) } }))
                    Text("Automatic picks a discrete card over an integrated one. Pick a device by name if you would rather keep the other one free.")
                        .font(.caption).foregroundColor(Theme.secondaryText)
                }
            } else {
                Text("No graphics device the port will use, so transcription runs on the processor. A software Vulkan driver (llvmpipe, lavapipe) is refused on purpose: it is slower than the processor.")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            }
            Divider()
            Text("Backend").font(.headline)
            Picker(of: TranscriptionBackend.allCases.map(\.displayName), selection: Binding(
                get: { remote.object.backend.displayName },
                set: { name in if let b = TranscriptionBackend.allCases.first(where: { $0.displayName == name }) { remote.object.backend = b } }))
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
            // Display names, not raw values: the picker used to read
            // "openai_compatible", and the endpoint presets behind it were not
            // offered at all, so the only way to reach a local model was to
            // know its URL and type it in.
            Picker(of: LLMTool.allCases.map(\.displayName), selection: Binding(
                get: { llm.object.tool.displayName },
                set: { name in
                    if let tool = LLMTool.allCases.first(where: { $0.displayName == name }) {
                        llm.object.tool = tool
                    }
                }))

            switch llm.object.tool {
            case .none:
                Text("AI features are off. Summaries, suggested names and Live AI do nothing until a provider is chosen.")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            case .claude, .cursor, .gemini:
                Text("Runs the \(llm.object.tool.displayName) command on this machine, using the login it already has. Leave the path empty unless the command is somewhere unusual.")
                    .font(.caption).foregroundColor(Theme.secondaryText)
                TextField("Executable path (optional)", text: Binding(get: { llm.object.executablePath }, set: { llm.object.executablePath = $0 }))
            case .openaiCompatible:
                Text("Any endpoint that speaks the OpenAI chat API, including one on this machine.")
                    .font(.caption).foregroundColor(Theme.secondaryText)
                Picker(of: OpenAIProvider.allCases.map(\.displayName), selection: Binding(
                    get: { llm.object.openAIProvider.displayName },
                    set: { name in
                        guard let provider = OpenAIProvider.allCases.first(where: { $0.displayName == name })
                        else { return }
                        llm.object.openAIProvider = provider
                        // The preset fills the URL in; Custom leaves whatever
                        // the user typed alone.
                        if provider != .custom { llm.object.openAIBaseURL = provider.baseURL }
                    }))
                TextField("Base URL", text: Binding(get: { llm.object.openAIBaseURL }, set: { llm.object.openAIBaseURL = $0 }))
                TextField("Model name", text: Binding(get: { llm.object.openAIModelName }, set: { llm.object.openAIModelName = $0 }))
                if llm.object.openAIProvider == .ollamaLocal {
                    Text("Ollama runs the model on this machine and needs no key. Start it with `ollama serve`, pull a model with `ollama pull mistral`, then put that name in the field above. Nothing leaves the machine.")
                        .font(.caption).foregroundColor(Theme.secondaryText)
                } else {
                    SecureField("API key", text: Binding(get: { llm.object.openAIAPIKey }, set: { llm.object.openAIAPIKey = $0 }))
                    Text("The transcript is sent to this endpoint when a summary is generated.")
                        .font(.caption).foregroundColor(Theme.danger)
                }
            }

            Divider()
            Text("Local AI, set up for you").font(.headline)
            Text("One button installs a model server on this machine, downloads an open model, and points the AI features at it. Nothing leaves the computer afterwards. The server and its models live under the app's cache and go with an uninstall purge.")
                .font(.caption).foregroundColor(Theme.secondaryText)
            Picker(of: LocalModel.catalogue.map(\.title), selection: Binding(
                get: { localModelTitle },
                set: { if let title = $0 { localModelTitle = title } }))
            if let chosen = LocalModel.catalogue.first(where: { $0.title == localModelTitle }) {
                Text("\(chosen.publisher), \(chosen.licence), about \(String(format: "%.1f", chosen.sizeGB)) GB, wants \(chosen.minimumRAMGB) GB of memory or more.")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            }
            HStack {
                Button(localAIBusy ? "Setting up..." : "Set up local AI") { setUpLocalAI() }
                Text(localAIStatus).font(.caption)
                    .foregroundColor(localAIStatus.hasPrefix("ready") ? Theme.success : Theme.secondaryText)
            }
            if !model.localAI.isRuntimeInstalled {
                Text("First time: the server is a 1.4 GB download, verified against its published digest before anything runs; the model is another few GB.")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            }

            Divider()
            HStack {
                Button("Test the provider") { testAIProvider() }
                Text(aiProviderStatus).font(.caption)
                    .foregroundColor(aiProviderStatus.hasPrefix("works") ? Theme.success : Theme.secondaryText)
            }
            Text(llm.object.isConfigured
                 ? "Ready. AI features can use this provider."
                 : "Not ready yet: choose a provider and fill in what it needs.")
                .font(.caption).foregroundColor(Theme.secondaryText)
        }
    }

    /// Runtime, server, model, then the settings, in that order: the provider
    /// is switched only once everything it points at is actually there.
    func setUpLocalAI() {
        guard !localAIBusy,
              let chosen = LocalModel.catalogue.first(where: { $0.title == localModelTitle }) else { return }
        localAIBusy = true
        localAIStatus = "starting"
        let managed = model.localAI
        let settings = model.llmSettings
        managed.onStage = { stage in
            Task { @MainActor in localAIStatus = stage.description }
        }
        Task { @MainActor in
            do {
                try await managed.setUp(model: chosen)
                settings.tool = .openaiCompatible
                settings.openAIProvider = .ollamaLocal
                settings.openAIBaseURL = ManagedOllama.baseURLForProvider
                settings.openAIModelName = chosen.name
                if !settings.summaryEnabled { settings.summaryEnabled = true }
                localAIStatus = "ready: \(chosen.title) on this machine, and selected as the provider"
            } catch {
                localAIStatus = "failed: \(error.localizedDescription)"
            }
            localAIBusy = false
        }
    }

    /// Sends one short prompt through whatever is configured, so a user can see
    /// that it answers before trusting it with a recording.
    func testAIProvider() {
        aiProviderStatus = "asking..."
        let settings = model.llmSettings
        Task { @MainActor in
            do {
                // The same entry point every AI feature uses, with the same
                // settings threaded through, so a green result here means the
                // summariser will get through too.
                let reply = try await LLMRunner.run(
                    tool: settings.tool,
                    prompt: "Reply with the single word: ready.",
                    transcript: "",
                    executablePathOverride: settings.executablePath.isEmpty ? nil : settings.executablePath,
                    model: settings.tool == .openaiCompatible ? settings.openAIModelName : nil,
                    timeout: 60,
                    openAIBaseURL: settings.tool == .openaiCompatible ? settings.openAIBaseURL : nil,
                    openAIAPIKey: settings.tool == .openaiCompatible ? settings.openAIAPIKey : nil)
                let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                aiProviderStatus = text.isEmpty ? "answered, but with nothing" : "works: \(text.prefix(40))"
            } catch {
                aiProviderStatus = "failed: \(error.localizedDescription)"
            }
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
