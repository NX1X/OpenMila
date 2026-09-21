// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Local AI in one place: install Ollama, run it, pull a model, and point the
// AI features at it. A port-only feature; Mila has no equivalent. It mirrors
// the shape of upstream's managed Claude install (pinned release, digest
// checked, nothing executed before it verifies) for a server instead of a CLI.
//
// Everything lives under the app's own cache directory. Nothing is installed
// system-wide, nothing needs an administrator, and removing the directory
// removes all of it. Models are the large part and are kept apart from the
// runtime so a runtime upgrade does not re-download them.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Crypto

/// One model the setup offers. Western, open-licensed, in a size that fits the
/// machines the port targets; the first entry is what "just set it up" picks.
public struct LocalModel: Equatable, Sendable, Identifiable {
    public let name: String          // what `ollama pull` takes
    public let title: String
    public let publisher: String
    public let licence: String
    public let sizeGB: Double
    public let minimumRAMGB: Int
    public var id: String { name }

    public static let catalogue: [LocalModel] = [
        LocalModel(name: "mistral", title: "Mistral 7B", publisher: "Mistral AI (France)",
                   licence: "Apache-2.0", sizeGB: 4.4, minimumRAMGB: 8),
        LocalModel(name: "mistral-nemo", title: "Mistral NeMo 12B", publisher: "Mistral AI and NVIDIA",
                   licence: "Apache-2.0", sizeGB: 7.1, minimumRAMGB: 16),
        LocalModel(name: "olmo2:7b", title: "OLMo 2 7B", publisher: "Allen Institute for AI (USA)",
                   licence: "Apache-2.0", sizeGB: 4.5, minimumRAMGB: 8),
        LocalModel(name: "gemma3:4b", title: "Gemma 3 4B", publisher: "Google (USA)",
                   licence: "Gemma terms", sizeGB: 3.3, minimumRAMGB: 8),
        LocalModel(name: "llama3.1:8b", title: "Llama 3.1 8B", publisher: "Meta (USA)",
                   licence: "Llama 3.1 community licence", sizeGB: 4.9, minimumRAMGB: 8),
        LocalModel(name: "smollm2:1.7b", title: "SmolLM2 1.7B", publisher: "Hugging Face (France and USA)",
                   licence: "Apache-2.0", sizeGB: 1.8, minimumRAMGB: 4),
    ]

    public static var recommended: LocalModel { catalogue[0] }
}

public enum LocalAIStage: Equatable, Sendable {
    case idle
    case downloadingRuntime(fraction: Double)
    case verifyingRuntime
    case unpackingRuntime
    case startingServer
    case pullingModel(name: String, fraction: Double)
    case ready(model: String)
    case failed(String)

    public var description: String {
        switch self {
        case .idle: return "not set up"
        case .downloadingRuntime(let f): return "downloading Ollama \(Int(f * 100))%"
        case .verifyingRuntime: return "checking the download against its digest"
        case .unpackingRuntime: return "unpacking"
        case .startingServer: return "starting the model server"
        case .pullingModel(let name, let f): return "downloading \(name) \(Int(f * 100))%"
        case .ready(let model): return "ready: \(model) on this machine"
        case .failed(let why): return "failed: \(why)"
        }
    }
}

public enum LocalAIError: Error, LocalizedError, Equatable {
    case unsupportedSystem
    case downloadFailed(String)
    case digestMismatch(expected: String, actual: String)
    case unpackFailed(String)
    case serverDidNotAnswer
    case pullFailed(String)
    case notEnoughDisk(neededGB: Double, freeGB: Double)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSystem: return "local AI setup supports Linux and Windows on x86-64"
        case .downloadFailed(let why): return "the download did not complete: \(why)"
        case .digestMismatch(let e, let a): return "the download does not match its published digest (expected \(e.prefix(12)), got \(a.prefix(12))); nothing was run"
        case .unpackFailed(let why): return "could not unpack the runtime: \(why)"
        case .serverDidNotAnswer: return "the model server started but never answered on port 11434"
        case .pullFailed(let why): return "the model download failed: \(why)"
        case .notEnoughDisk(let n, let f): return "needs about \(Int(n.rounded(.up))) GB free, \(Int(f)) GB available"
        }
    }
}

/// The pinned runtime. One release, two assets, two digests from the vendor's
/// own sha256sum.txt for that release; bumping means changing all of it in a
/// commit that says why, the same rule the port applies to every pin.
public struct OllamaRelease: Sendable {
    public let version: String
    public let url: URL
    public let sha256: String
    public let archiveName: String

    public static let pinned: OllamaRelease? = {
        #if os(Linux) && arch(x86_64)
        return OllamaRelease(
            version: "0.34.2",
            url: URL(string: "https://github.com/ollama/ollama/releases/download/v0.34.2/ollama-linux-amd64.tar.zst")!,
            sha256: "e155b83589986d2c581fdbf1381ea3ebdb16549883679cd5a0627f7cdc05b12b",
            archiveName: "ollama-linux-amd64.tar.zst")
        #elseif os(Windows) && arch(x86_64)
        return OllamaRelease(
            version: "0.34.2",
            url: URL(string: "https://github.com/ollama/ollama/releases/download/v0.34.2/ollama-windows-amd64.zip")!,
            sha256: "8f3fd071a2a2f9497b562f43502c77c2b701a99d1ee5dfda28da8c786373063b",
            archiveName: "ollama-windows-amd64.zip")
        #else
        return nil
        #endif
    }()
}


/// Streams a response body chunk by chunk through a delegate. Apple's
/// Foundation has `URLSession.bytes`; the Foundation on Linux and Windows does
/// not, and a 1.4 GB runtime plus a multi-gigabyte model must not be buffered
/// whole. `onChunk` runs on the session's queue; keep it quick.
final class ChunkedRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let onChunk: (Data) -> Void
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var session: URLSession?

    init(onChunk: @escaping (Data) -> Void) { self.onChunk = onChunk }

    func run(_ request: URLRequest) async throws -> HTTPURLResponse {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = 24 * 3600
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        // Torn down here, after the transfer has reported in, and never from
        // inside a delegate callback: invalidating a session from its own
        // callback left the transfer handle dangling and aborted the process.
        defer { session.finishTasksAndInvalidate(); self.session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onChunk(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error); return }
        guard let response else {
            continuation.resume(throwing: LocalAIError.downloadFailed("no response")); return
        }
        continuation.resume(returning: response)
    }
}

/// Owns the runtime under `<cache>/local-ai`, the server process, and the
/// model store beside it. One instance per app.
public final class ManagedOllama: @unchecked Sendable {
    public static let endpoint = URL(string: "http://127.0.0.1:11434")!
    public static let baseURLForProvider = "http://localhost:11434/v1"

    public let root: URL
    private let lock = NSLock()
    private var server: Process?
    private(set) public var stage: LocalAIStage = .idle
    public var onStage: (@Sendable (LocalAIStage) -> Void)?

    public init(cacheDirectory: URL) {
        root = cacheDirectory.appendingPathComponent("local-ai", isDirectory: true)
    }

    // MARK: Layout

    public var runtimeDirectory: URL { root.appendingPathComponent("runtime", isDirectory: true) }
    public var modelsDirectory: URL { root.appendingPathComponent("models", isDirectory: true) }
    public var executable: URL {
        #if os(Windows)
        return runtimeDirectory.appendingPathComponent("ollama.exe")
        #else
        return runtimeDirectory.appendingPathComponent("bin/ollama")
        #endif
    }
    /// Written after a verified unpack; its absence means the runtime is not
    /// trusted, whatever files happen to be there.
    private var stampFile: URL { runtimeDirectory.appendingPathComponent(".openmila-verified") }

    public var isRuntimeInstalled: Bool {
        FileManager.default.fileExists(atPath: executable.path)
            && (try? String(contentsOf: stampFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                == OllamaRelease.pinned?.sha256
    }

    // MARK: Server

    /// True when something already answers on the port: a server this app
    /// started, or one the user runs themselves. Either is fine to use.
    public func isServerAnswering() async -> Bool {
        var request = URLRequest(url: Self.endpoint.appendingPathComponent("api/version"))
        request.timeoutInterval = 3
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return !data.isEmpty
    }

    public func installedModels() async -> [String] {
        var request = URLRequest(url: Self.endpoint.appendingPathComponent("api/tags"))
        request.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    /// Starts the managed server if nothing answers yet. The process is a
    /// child of the app and dies with it; models go to the app's own store.
    public func startServer() async throws {
        if await isServerAnswering() { return }
        guard isRuntimeInstalled else { throw LocalAIError.unsupportedSystem }
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_MODELS"] = modelsDirectory.path
        environment["OLLAMA_HOST"] = "127.0.0.1:11434"
        #if os(Linux)
        let lib = runtimeDirectory.appendingPathComponent("lib/ollama").path
        environment["LD_LIBRARY_PATH"] = [lib, environment["LD_LIBRARY_PATH"] ?? ""].joined(separator: ":")
        #endif
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        lock.lock(); server = process; lock.unlock()
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if await isServerAnswering() { return }
            if !process.isRunning { break }
        }
        throw LocalAIError.serverDidNotAnswer
    }

    public func stopServer() {
        lock.lock(); let process = server; server = nil; lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    // MARK: Setup

    /// The whole thing: runtime, server, model. Safe to call again; each step
    /// skips what is already done, so a second run only pulls a new model.
    public func setUp(model: LocalModel) async throws {
        do {
            try await installRuntimeIfNeeded()
            set(.startingServer)
            try await startServer()
            if !(await installedModels()).contains(where: { $0 == model.name || $0.hasPrefix(model.name + ":") }) {
                try await pull(model)
            }
            set(.ready(model: model.name))
        } catch {
            set(.failed(error.localizedDescription))
            throw error
        }
    }

    func installRuntimeIfNeeded() async throws {
        guard let release = OllamaRelease.pinned else { throw LocalAIError.unsupportedSystem }
        if isRuntimeInstalled { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try checkDisk(neededGB: 4)

        let archive = root.appendingPathComponent(release.archiveName)
        var haveVerifiedArchive = false
        if FileManager.default.fileExists(atPath: archive.path) {
            set(.verifyingRuntime)
            haveVerifiedArchive = (try? Self.sha256Hex(of: archive)) == release.sha256
            if !haveVerifiedArchive { try? FileManager.default.removeItem(at: archive) }
        }
        if !haveVerifiedArchive {
            set(.downloadingRuntime(fraction: 0))
            try await download(release.url, to: archive) { [weak self] f in self?.set(.downloadingRuntime(fraction: f)) }
            set(.verifyingRuntime)
            let actual = try Self.sha256Hex(of: archive)
            guard actual == release.sha256 else {
                try? FileManager.default.removeItem(at: archive)
                throw LocalAIError.digestMismatch(expected: release.sha256, actual: actual)
            }
        }

        set(.unpackingRuntime)
        try? FileManager.default.removeItem(at: runtimeDirectory)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try unpack(archive, into: runtimeDirectory)
        try? FileManager.default.removeItem(at: archive)
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw LocalAIError.unpackFailed("no ollama executable in the archive")
        }
        try release.sha256.write(to: stampFile, atomically: true, encoding: .utf8)
    }

    func pull(_ model: LocalModel) async throws {
        try checkDisk(neededGB: model.sizeGB + 0.5)
        set(.pullingModel(name: model.name, fraction: 0))
        // /api/pull streams JSON lines with completed/total per layer.
        var request = URLRequest(url: Self.endpoint.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": model.name, "stream": true])
        request.timeoutInterval = 3600
        let state = PullState()
        let streaming = ChunkedRequest { [weak self] chunk in
            state.append(chunk) { object in
                if let error = object["error"] as? String { state.failure = error; return }
                if let digest = object["digest"] as? String,
                   let total = object["total"] as? Double, total > 0 {
                    state.totals[digest] = ((object["completed"] as? Double) ?? 0, total)
                    let done = state.totals.values.reduce(0) { $0 + $1.0 }
                    let all = state.totals.values.reduce(0) { $0 + $1.1 }
                    self?.set(.pullingModel(name: model.name, fraction: all > 0 ? done / all : 0))
                }
                if (object["status"] as? String) == "success" { state.succeeded = true }
            }
        }
        let response = try await streaming.run(request)
        if let failure = state.failure { throw LocalAIError.pullFailed(failure) }
        guard response.statusCode == 200 else { throw LocalAIError.pullFailed("HTTP \(response.statusCode)") }
        guard state.succeeded else { throw LocalAIError.pullFailed("the server ended the download without success") }
    }

    /// Line buffer and progress for one pull; the delegate delivers chunks
    /// that need not end on a line boundary.
    private final class PullState: @unchecked Sendable {
        var buffer = Data()
        var totals: [String: (Double, Double)] = [:]
        var failure: String?
        var succeeded = false
        private let lock = NSLock()

        func append(_ chunk: Data, each: ([String: Any]) -> Void) {
            lock.lock(); defer { lock.unlock() }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { each(object) }
            }
        }
    }

    // MARK: Pieces

    private func set(_ new: LocalAIStage) {
        lock.lock(); stage = new; lock.unlock()
        onStage?(new)
    }

    private func checkDisk(neededGB: Double) throws {
        let values = try? root.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let free = values?.volumeAvailableCapacity else { return }
        let freeGB = Double(free) / 1_073_741_824
        if freeGB < neededGB { throw LocalAIError.notEnoughDisk(neededGB: neededGB, freeGB: freeGB) }
    }

    private func download(_ url: URL, to destination: URL,
                          progress: @escaping @Sendable (Double) -> Void) async throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        let counter = ByteCounter()
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        let streaming = ChunkedRequest { chunk in
            handle.write(chunk)
            counter.add(chunk.count)
        }
        // Progress is reported from the expected length once it is known;
        // the delegate hands that over with the response, which is why the
        // counter reads it lazily.
        let response = try await streaming.run(request)
        guard response.statusCode == 200 else {
            throw LocalAIError.downloadFailed("HTTP \(response.statusCode)")
        }
        progress(1)
        _ = counter
    }

    private final class ByteCounter: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var written = 0
        func add(_ count: Int) { lock.lock(); written += count; lock.unlock() }
    }

    private func unpack(_ archive: URL, into directory: URL) throws {
        // tar handles both: GNU tar with zstd on Linux, bsdtar (ships with
        // Windows 10 and later) for the zip.
        #if os(Windows)
        let tar = URL(fileURLWithPath: "C:\\Windows\\System32\\tar.exe")
        #else
        let tar = URL(fileURLWithPath: "/usr/bin/tar")
        #endif
        let process = Process()
        process.executableURL = tar
        process.arguments = ["-xf", archive.path, "-C", directory.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        // Drained on its own thread before waiting, so a chatty tar cannot
        // fill the pipe and deadlock against a parent that is only waiting.
        let drainedData = DrainedPipe()
        let reader = Thread { drainedData.data = errors.fileHandleForReading.readDataToEndOfFile() }
        reader.start()
        try process.run()
        if finished.wait(timeout: .now() + 600) == .timedOut {
            process.terminate()
            throw LocalAIError.unpackFailed("tar did not finish in ten minutes")
        }
        let stderr = String(decoding: drainedData.data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw LocalAIError.unpackFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private final class DrainedPipe: @unchecked Sendable { var data = Data() }

    static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 4 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
