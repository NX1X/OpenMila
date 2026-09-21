// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Headless end-to-end checks of the real code paths the desktop app uses,
// against the real data root, for a machine without a display or microphone.
//
//   openmila-selftest models            download the English model (large-v3-turbo) via ModelManager
//   openmila-selftest import <dir>      watched-folder import of <dir>, then transcription
//   openmila-selftest summarize [--provider claude|ollama] [--model name] [--endpoint url]
//   openmila-selftest local-ai [--model name] [--cache dir]   managed Ollama end to end
//   openmila-selftest summarize         summarise the newest recording with the configured `claude` CLI
//   openmila-selftest diarize <file>    install torch if needed, then label speakers
//   openmila-selftest list              show the store
//
// Settings the tests need are kept in a private UserDefaults suite, so the
// app's own settings are untouched. Recordings land in the real library,
// titled so they are easy to find and delete.

import Foundation
import OpenMilaLogging
import LocalAI
import TranscriptionCore
@testable import Mila

let args = Array(CommandLine.arguments.dropFirst())
OpenMilaLog.install(processName: "openmila-selftest", version: "dev", alsoStderr: false)

func say(_ text: String) { print(text); fflush(stdout) }

/// `--name value` out of the argument list, for the few commands that take one.
func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}
func fail(_ text: String) -> Never { FileHandle.standardError.write(Data((text + "\n").utf8)); exit(1) }

@MainActor
func dataRoot() -> URL {
    let base = ProcessInfo.processInfo.environment["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
    return base.appendingPathComponent("Mila", isDirectory: true)
}

@MainActor
func suite() -> UserDefaults {
    let name = "io.github.nx1x.openmila.selftest"
    return UserDefaults(suiteName: name)!
}

@MainActor
func waitFor(_ what: String, timeout: TimeInterval, poll: TimeInterval = 1, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
    }
    say("timed out waiting for \(what)")
    return false
}

@MainActor
func run() async {
    let root = dataRoot()
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let defaults = suite()
    let models = ModelManager(modelsDirectory: root.appendingPathComponent("Models", isDirectory: true), defaults: defaults)

    switch args.first {
    case "models":
        let model = WhisperModel.openaiTurbo
        models.refreshInstalled()
        if models.isInstalled(model) { say("already installed: \(model.name)"); return }
        say("downloading \(model.displayName) through ModelManager (SHA-256 checked on completion)...")
        models.download(model)
        var lastTen = -1
        let ok = await waitFor("the download", timeout: 3600, poll: 2) {
            if let p = models.downloads[model.name] {
                let ten = Int(p * 10)
                if ten != lastTen { lastTen = ten; say("  \(ten * 10)%") }
            }
            if let err = models.lastDownloadErrors[model.name] { fail("download failed: \(err)") }
            return models.isInstalled(model)
        }
        say(ok ? "installed and verified: \(models.url(for: model).path)" : "not installed")

    case "import":
        guard args.count >= 2 else { fail("usage: openmila-selftest import <folder>") }
        let folder = URL(fileURLWithPath: args[1])
        models.refreshInstalled()
        guard models.isInstalled(.openaiTurbo) else { fail("run `openmila-selftest models` first") }
        models.setSelected(.openaiTurbo)

        let store = RecordingStore(rootDirectory: root)
        let language = RecordingLanguageSettings(defaults: defaults)
        language.current = .english
        let diarization = DiarizationSettings(defaults: defaults)
        let remote = RemoteTranscriptionSettings(defaults: defaults)
        remote.backend = .local
        let transcription = TranscriptionService(store: store, modelManager: models,
                                                 diarizationSettings: diarization, remoteSettings: remote)
        let settings = VoiceMemosSettings(defaults: defaults)
        settings.startDate = Date(timeIntervalSince1970: 0)
        guard settings.grantFolder(folder) else { fail("could not use folder \(folder.path)") }
        settings.includeUnfiled = true
        // Select every subfolder, as a user ticking all of them in Settings would.
        for sub in (try? VoiceMemosLibrary(recordingsDirectory: folder).folders()) ?? [] {
            settings.setFolder(sub.uuid, selected: true)
        }
        settings.isEnabled = true

        let before = Set(store.recordings.map(\.id))
        let importer = VoiceMemosImporter(store: store, transcription: transcription,
                                          settings: settings, languageSettings: language)
        importer.start()
        say("watching \(folder.path)")
        // Files imported by an earlier run are deduplicated, so only new ones count.
        let known = Set(store.recordings.compactMap(\.voiceMemoUniqueID))
        let expected = ((try? VoiceMemosLibrary(recordingsDirectory: folder).fetchAllRecordings()) ?? [])
            .filter { !known.contains($0.uniqueID) }.count
        say("new files to import: \(expected)")
        if expected == 0 { say("nothing new; everything in the folder is already imported"); return }
        guard await waitFor("the import", timeout: 120, { store.recordings.filter { !before.contains($0.id) }.count >= expected }) else {
            fail("nothing imported: \(importer.lastError ?? "no error reported")")
        }
        let added = store.recordings.filter { !before.contains($0.id) }
        say("imported \(added.count): \(added.map(\.title).joined(separator: ", ")) into folder \"\(added.first?.folder ?? "-")\"")
        let done = await waitFor("transcription", timeout: 1800, poll: 2) {
            added.allSatisfy { r in
                let s = store.recordings.first { $0.id == r.id }?.status
                return s == .completed || s == .failed
            }
        }
        for r in added {
            let current = store.recordings.first { $0.id == r.id }
            say("--- \(r.title): \(current?.status.rawValue ?? "?") (\(String(format: "%.1f", current?.duration ?? 0)) s)")
            say(current?.fullText.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        importer.stop()
        if !done { exit(1) }

    case "summarize":
        let store = RecordingStore(rootDirectory: root)
        guard let target = store.recordings.filter({ $0.deletedAt == nil && $0.status == .completed && !$0.fullText.isEmpty })
            .max(by: { $0.createdAt < $1.createdAt }) else { fail("no completed recording to summarise") }
        let llm = LLMSettings(defaults: defaults)
        llm.summaryEnabled = true
        // --provider ollama exercises the path a privacy-minded user actually
        // wants: an OpenAI-compatible endpoint on this machine, no key, no
        // network. Anything else keeps the claude CLI, which is the default
        // this harness had.
        let provider = option("--provider", in: args) ?? "claude"
        let describedProvider: String
        if provider == "ollama" {
            llm.tool = .openaiCompatible
            llm.openAIProvider = .ollamaLocal
            llm.openAIBaseURL = option("--endpoint", in: args) ?? OpenAIProvider.ollamaLocal.baseURL
            llm.openAIModelName = option("--model", in: args) ?? "mistral"
            describedProvider = "Ollama at \(llm.openAIBaseURL), model \(llm.openAIModelName)"
        } else {
            llm.tool = .claude
            describedProvider = "the claude CLI"
        }
        let live = LiveAISettings(defaults: defaults)
        let summarizer = RecordingSummarizer(store: store, llmSettings: llm, liveAISettings: live)
        say("summarising \"\(target.title)\" with \(describedProvider)...")
        summarizer.regenerate(target)
        _ = await waitFor("the summary", timeout: 300, poll: 2) { !summarizer.isSummarizing(target.id) && (store.recordings.first { $0.id == target.id }?.summary?.isEmpty == false) }
        let updated = store.recordings.first { $0.id == target.id }
        say("summary: \(updated?.summary ?? "(none)")")
        for item in updated?.actionItems ?? [] { say("  action: \(item.text)") }
        if updated?.summary?.isEmpty != false { exit(1) }

    case "diarize":
        guard args.count >= 2 else { fail("usage: openmila-selftest diarize <file.wav>") }
        let audio = URL(fileURLWithPath: args[1])
        let settings = DiarizationSettings(defaults: defaults)
        settings.isEnabled = true
        let python = SpeakerDiarizer.resolvePython(userConfigured: settings.pythonPath)
        say("python: \(python)")
        guard python.contains("PythonRuntime") else {
            fail("no bundled runtime found; run diarization/build-bundle-linux.sh and link it beside the binary")
        }
        let bootstrap = DiarizationBootstrap(bundledPython: python)
        bootstrap.refreshReadyState()
        if !bootstrap.isReady {
            say("installing torch \(DiarizationBootstrap.torchVersion) into the user site-packages (about 200 MB)...")
            await bootstrap.bootstrapIfNeeded()
            say("bootstrap stage: \(bootstrap.stage)")
        }
        guard bootstrap.isReady else { fail("torch did not install: \(bootstrap.stage)") }
        say("verifying the pipeline...")
        let verification = try? await SpeakerDiarizer.verifySetup(pythonPath: python)
        say("verify: \(verification.map { String(describing: $0) } ?? "no result")")
        say("diarizing \(audio.lastPathComponent)...")
        let turns: [SpeakerTurn]
        do {
            turns = try await SpeakerDiarizer.diarize(wavURL: audio, pythonPath: python)
        } catch {
            fail("diarization failed: \(error.localizedDescription)")
        }
        if turns.isEmpty { say("no speaker turns returned") } 
        for turn in turns {
            say(String(format: "  %6.2f - %6.2f  %@", turn.start, turn.end, turn.speaker))
        }
        if turns.isEmpty { exit(1) }

    case "local-ai":
        // The whole managed path, headless: runtime, server, model, then one
        // summary through it. `--model` picks from the catalogue by name;
        // `--cache` overrides where the runtime and models go.
        // The app's cache directory, as LinuxAppPaths resolves it: the runtime
        // and models are regenerable and belong there, not with the data.
        let cache = option("--cache", in: args).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? (ProcessInfo.processInfo.environment["XDG_CACHE_HOME"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache"))
                .appendingPathComponent("openmila", isDirectory: true)
        let wanted = option("--model", in: args) ?? LocalModel.recommended.name
        guard let model = LocalModel.catalogue.first(where: { $0.name == wanted }) else {
            fail("unknown model \(wanted); catalogue: \(LocalModel.catalogue.map(\.name).joined(separator: ", "))")
        }
        let managed = ManagedOllama(cacheDirectory: cache)
        var lastLine = ""
        managed.onStage = { stage in
            let line = stage.description
            if line != lastLine { lastLine = line; say("  \(line)") }
        }
        say("local AI under \(managed.root.path)")
        say("runtime installed: \(managed.isRuntimeInstalled), server answering: \(await managed.isServerAnswering())")
        do {
            try await managed.setUp(model: model)
        } catch {
            fail("local AI setup failed: \(error.localizedDescription)")
        }
        say("models: \(await managed.installedModels().joined(separator: ", "))")
        let llm = LLMSettings(defaults: defaults)
        llm.tool = .openaiCompatible
        llm.openAIProvider = .ollamaLocal
        llm.openAIBaseURL = ManagedOllama.baseURLForProvider
        llm.openAIModelName = model.name
        do {
            let reply = try await LLMRunner.run(tool: .openaiCompatible, prompt: "Reply with the single word: ready.",
                                                transcript: "", executablePathOverride: nil, model: model.name,
                                                timeout: 300, openAIBaseURL: llm.openAIBaseURL, openAIAPIKey: nil)
            say("provider answered: \(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))")
        } catch {
            fail("the provider did not answer: \(error.localizedDescription)")
        }
        managed.stopServer()

    case "list":
        let store = RecordingStore(rootDirectory: root)
        say("store: \(store.recordingsDirectory.path)  recordings: \(store.recordings.count)  folders: \(store.folders)")
        for r in store.recordings {
            say("\(r.id)  \(r.status.rawValue)  \(r.title)  summary=\(r.summary == nil ? "no" : "yes")")
        }

    default:
        say("usage: openmila-selftest models | import <folder> | summarize | diarize <file> | list")
    }
}

let done = DispatchSemaphore(value: 0)
Task { @MainActor in
    await run()
    done.signal()
}
// Keep the main thread serving the main actor while the task runs.
while done.wait(timeout: .now()) == .timedOut {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
exit(0)
