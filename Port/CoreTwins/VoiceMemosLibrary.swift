// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `Mila/VoiceMemos/VoiceMemosLibrary.swift`. Upstream reads the
// SQLite database of Apple's Voice Memos app. OpenMila adapts the feature to
// "watched folders": the library is a directory the user syncs recordings
// into (Syncthing, Nextcloud, iCloud Drive for Windows, a phone mounted over
// USB). Same API, so upstream's `VoiceMemosImporter` runs unchanged:
//   - a "folder" is a first-level subdirectory; files at the top level are
//     "unfiled";
//   - a memo's unique id is its relative path plus size and modification
//     time, which is what makes the importer's dedup survive restarts;
//   - duration comes from the WAV header, or ffprobe for other formats.

import Foundation
import TranscriptionCore

struct VoiceMemosLibrary {
    let recordingsDirectory: URL

    static let audioExtensions: Set<String> = ["wav", "m4a", "mp3", "ogg", "opus", "flac", "aac", "mp4", "webm"]

    init(recordingsDirectory: URL = VoiceMemosLibrary.defaultRecordingsDirectory) {
        self.recordingsDirectory = recordingsDirectory
    }

    /// Suggested starting point for the folder picker, and what Settings
    /// offers when the user has not chosen anything yet. Upstream has one
    /// answer here (the folder iCloud syncs Voice Memos into); off a Mac there
    /// is no such folder, so the port proposes one rather than leaving the
    /// field empty - an empty field is how a user ends up watching their whole
    /// home directory.
    ///
    /// `XDG_MUSIC_DIR` first, because a localised desktop calls that directory
    /// something other than "Music" and Foundation does not read the user's
    /// XDG config.
    static var defaultRecordingsDirectory: URL {
        let fm = FileManager.default
        if let music = xdgMusicDirectory, fm.fileExists(atPath: music.path) {
            return music.appendingPathComponent("Recordings", isDirectory: true)
        }
        if let music = fm.urls(for: .musicDirectory, in: .userDomainMask).first, fm.fileExists(atPath: music.path) {
            return music.appendingPathComponent("Recordings", isDirectory: true)
        }
        return fm.homeDirectoryForCurrentUser.appendingPathComponent("Recordings", isDirectory: true)
    }

    /// `XDG_MUSIC_DIR` from the environment, else from `user-dirs.dirs`, where
    /// it is written as `XDG_MUSIC_DIR="$HOME/Musik"`.
    static var xdgMusicDirectory: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let value = ProcessInfo.processInfo.environment["XDG_MUSIC_DIR"], !value.isEmpty {
            return URL(fileURLWithPath: expandingHome(value, home: home), isDirectory: true)
        }
        let config = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
        } ?? home.appendingPathComponent(".config", isDirectory: true)
        guard let text = try? String(contentsOf: config.appendingPathComponent("user-dirs.dirs"),
                                    encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("XDG_MUSIC_DIR=") {
            let raw = line.dropFirst("XDG_MUSIC_DIR=".count)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !raw.isEmpty else { continue }
            return URL(fileURLWithPath: expandingHome(raw, home: home), isDirectory: true)
        }
        return nil
    }

    private static func expandingHome(_ path: String, home: URL) -> String {
        if path == "$HOME" || path == "~" { return home.path }
        for prefix in ["$HOME/", "~/"] where path.hasPrefix(prefix) {
            return home.appendingPathComponent(String(path.dropFirst(prefix.count))).path
        }
        return path
    }

    var databaseDisplayPath: String { recordingsDirectory.path }
    var recordingsDirectoryDisplayPath: String { recordingsDirectory.path }

    enum Availability: Equatable {
        case available
        case databaseMissing
        case accessDenied(reason: String)
    }

    var availability: Availability {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: recordingsDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            return .databaseMissing
        }
        return FileManager.default.isReadableFile(atPath: recordingsDirectory.path)
            ? .available : .accessDenied(reason: "not readable")
    }

    var isAvailable: Bool { availability == .available }

    struct Folder: Identifiable, Hashable {
        let uuid: String
        let name: String
        let count: Int
        var id: String { uuid }
    }

    struct Memo: Identifiable, Hashable {
        let uniqueID: String
        let fileURL: URL
        let folderUUID: String?
        let title: String
        let duration: Double
        let date: Date
        var id: String { uniqueID }
        var isComposition: Bool { false }
    }

    enum LibraryError: LocalizedError, Equatable {
        case databaseMissing
        case accessDenied(String)
        case openFailed(String)
        case schemaUnsupported

        var errorDescription: String? {
            switch self {
            case .databaseMissing: return "The watched folder does not exist."
            case .accessDenied: return "OpenMila cannot read the watched folder. Check its permissions in Settings > Watched Folders."
            case .openFailed(let msg): return "Could not read the watched folder: \(msg)"
            case .schemaUnsupported: return "The watched folder has an unexpected layout."
            }
        }
    }

    func folders() throws -> [Folder] {
        try checkAvailable()
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        return entries.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  !url.lastPathComponent.hasPrefix(".") else { return nil }
            let count = ((try? fm.contentsOfDirectory(atPath: url.path)) ?? [])
                .filter { Self.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }.count
            return Folder(uuid: url.lastPathComponent, name: url.lastPathComponent, count: count)
        }.sorted { $0.name < $1.name }
    }

    func unfiledCount() throws -> Int {
        try fetchAllRecordings().filter { $0.folderUUID == nil }.count
    }

    func recordings(folderUUIDs: Set<String>, includeUnfiled: Bool) throws -> [Memo] {
        try fetchAllRecordings().filter { memo in
            if let folder = memo.folderUUID { return folderUUIDs.contains(folder) }
            return includeUnfiled
        }
    }

    func fetchAllRecordings() throws -> [Memo] {
        try checkAvailable()
        var memos: [Memo] = []
        try scan(directory: recordingsDirectory, folderUUID: nil, into: &memos)
        for folder in try folders() {
            try scan(directory: recordingsDirectory.appendingPathComponent(folder.uuid), folderUUID: folder.uuid, into: &memos)
        }
        return memos.sorted { $0.date > $1.date }
    }

    private func checkAvailable() throws {
        switch availability {
        case .available: return
        case .databaseMissing: throw LibraryError.databaseMissing
        case .accessDenied(let reason): throw LibraryError.accessDenied(reason)
        }
    }

    private func scan(directory: URL, folderUUID: String?, into memos: inout [Memo]) throws {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true,
                  Self.audioExtensions.contains(url.pathExtension.lowercased()),
                  !url.lastPathComponent.hasPrefix(".") else { continue }
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate ?? Date()
            let relative = (folderUUID.map { $0 + "/" } ?? "") + url.lastPathComponent
            memos.append(Memo(
                uniqueID: "\(relative)#\(size)#\(Int(modified.timeIntervalSince1970))",
                fileURL: url,
                folderUUID: folderUUID,
                title: url.deletingPathExtension().lastPathComponent,
                duration: Self.duration(of: url),
                date: values?.creationDate ?? modified))
        }
    }

    /// WAV headers are read directly; anything else asks ffprobe. Unknown
    /// durations report as one minute so the importer's "skip clips shorter
    /// than a few seconds" rule never drops a file it could not measure.
    static func duration(of url: URL) -> Double {
        if url.pathExtension.lowercased() == "wav",
           let handle = try? FileHandle(forReadingFrom: url),
           let header = try? handle.read(upToCount: 44), header.count == 44 {
            let sampleRate = header[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            let blockAlign = header[32..<34].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            let dataBytes = header[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            if sampleRate > 0, blockAlign > 0, dataBytes > 0 {
                return Double(dataBytes) / Double(sampleRate) / Double(blockAlign)
            }
        }
        if let ffprobe = ["/usr/bin/ffprobe", "/usr/local/bin/ffprobe"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffprobe)
            process.arguments = ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", url.path]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let text = String(data: data, encoding: .utf8), let seconds = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return seconds
                }
            }
        }
        return 60
    }
}
