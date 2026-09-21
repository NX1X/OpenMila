// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Tests for the port twins compiled into the Mila module.

import Foundation
import TranscriptionCore
import XCTest
@testable import Mila

final class WatchedFolderLibraryTests: XCTestCase {
    func test_scans_top_level_and_subfolders_with_stable_ids() throws {
        let root = TestSupport.makeTempRoot(label: "watched")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Work"), withIntermediateDirectories: true)
        try TestSupport.writeSineWav(at: root.appendingPathComponent("memo one.wav"), durationSeconds: 2)
        try TestSupport.writeSineWav(at: root.appendingPathComponent("Work/standup.wav"), durationSeconds: 4)
        try Data("not audio".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let library = VoiceMemosLibrary(recordingsDirectory: root)
        XCTAssertTrue(library.isAvailable)
        let all = try library.fetchAllRecordings()
        XCTAssertEqual(all.count, 2)
        let work = try library.recordings(folderUUIDs: ["Work"], includeUnfiled: false)
        XCTAssertEqual(work.map(\.title), ["standup"])
        XCTAssertEqual(work[0].duration, 4, accuracy: 0.01)
        XCTAssertEqual(try library.unfiledCount(), 1)
        XCTAssertEqual(try library.folders().map(\.name), ["Work"])
        // Same file, same id across scans; the importer's dedup depends on it.
        XCTAssertEqual(try library.fetchAllRecordings().map(\.uniqueID), all.map(\.uniqueID))
        try? FileManager.default.removeItem(at: root)
    }

    func test_missing_folder_is_reported_not_crashed() {
        let library = VoiceMemosLibrary(recordingsDirectory: URL(fileURLWithPath: "/nonexistent/openmila-\(UUID())"))
        XCTAssertEqual(library.availability, .databaseMissing)
        XCTAssertThrowsError(try library.fetchAllRecordings())
    }
}

/// The folder Settings offers when the user has chosen nothing. It has to be a
/// real suggestion: an empty field is how someone ends up watching their whole
/// home directory, which then treats every folder in it as an import source.
final class SuggestedWatchedFolderTests: XCTestCase {
    // XDG_MUSIC_DIR is a freedesktop convention and the reader only consults it
    // off Windows, so the two tests that drive it are Linux-side. `setenv` is
    // POSIX and does not exist on Windows at all, which is the other half of
    // the reason.
    #if !os(Windows)
    func test_xdg_music_dir_wins_when_it_exists() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("openmila-xdg-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        setenv("XDG_MUSIC_DIR", root.path, 1)
        defer { unsetenv("XDG_MUSIC_DIR") }
        XCTAssertEqual(VoiceMemosLibrary.defaultRecordingsDirectory.path,
                       root.appendingPathComponent("Recordings").path)
    }

    /// `user-dirs.dirs` writes the path with $HOME and quotes around it.
    func test_a_home_relative_xdg_value_is_expanded() {
        setenv("XDG_MUSIC_DIR", "$HOME/Musik", 1)
        defer { unsetenv("XDG_MUSIC_DIR") }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(VoiceMemosLibrary.xdgMusicDirectory?.path, home + "/Musik")
    }
    #endif

    /// Whatever the machine looks like, and on either system, the suggestion is
    /// never the home directory itself. No environment is touched here, so this
    /// one runs everywhere.
    func test_the_suggestion_is_never_the_home_directory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertNotEqual(VoiceMemosLibrary.defaultRecordingsDirectory.path, home)
    }
}

final class DirectoryWatcherTwinTests: XCTestCase {
    func test_reports_a_new_file() throws {
        let root = TestSupport.makeTempRoot(label: "watcher")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fired = expectation(description: "changed")
        fired.assertForOverFulfill = false
        let watcher = DirectoryWatcher(path: root.path, latency: 0.2) { fired.fulfill() }
        watcher.start()
        try Data([0]).write(to: root.appendingPathComponent("new.wav"))
        wait(for: [fired], timeout: 5)
        watcher.stop()
        try? FileManager.default.removeItem(at: root)
    }
}

final class FileTranscriberTwinTests: XCTestCase {
    @MainActor
    func test_import_copies_as_canonical_wav_and_adds_recording() async throws {
        let root = TestSupport.makeTempRoot(label: "import")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("stereo.wav")
        try TestSupport.writeStereo48kSineWav(at: source, durationSeconds: 1)
        let store = RecordingStore(rootDirectory: root.appendingPathComponent("store"))
        let recording = try await FileTranscriber.importFile(at: source, into: store, language: .english,
                                                             source: .voiceMemo, folder: "Voice Memos")
        XCTAssertEqual(recording.duration, 1, accuracy: 0.01)
        XCTAssertEqual(recording.folder, "Voice Memos")
        XCTAssertTrue(store.folders.contains("Voice Memos"))
        let samples = try WAVReader.loadSamples(url: store.audioURL(for: recording))
        XCTAssertEqual(samples.count, 16_000)
        try? FileManager.default.removeItem(at: root)
    }
}
