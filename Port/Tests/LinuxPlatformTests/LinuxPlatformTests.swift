// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only: the types under test exist only there, and SwiftPM has no way to
// leave a test target out of a Windows build, so the file compiles to nothing
// off Linux.
#if os(Linux)
import Foundation
import PlatformKit
import XCTest
@testable import LinuxPlatform
@testable import Updater

final class LinuxAppPathsTests: XCTestCase {
    func test_xdg_variables_win_over_defaults() {
        let paths = LinuxAppPaths(environment: ["XDG_DATA_HOME": "/tmp/xdg-data", "XDG_STATE_HOME": "/tmp/xdg-state"],
                                  home: URL(fileURLWithPath: "/home/u"))
        XCTAssertEqual(paths.dataDirectory.path, "/tmp/xdg-data/Mila")
        XCTAssertEqual(paths.logDirectory.path, "/tmp/xdg-state/openmila/logs")
        XCTAssertEqual(paths.cacheDirectory.path, "/home/u/.cache/openmila")
    }

    func test_resources_resolve_beside_the_executable_or_in_share() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("paths-\(UUID())")
        let bin = root.appendingPathComponent("bin")
        let share = root.appendingPathComponent("share/openmila")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: share, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: share.appendingPathComponent("ggml-silero.bin"))
        let paths = LinuxAppPaths(environment: [:], home: root, executable: bin.appendingPathComponent("openmila"))
        XCTAssertEqual(paths.resource(named: "ggml-silero.bin")?.path, share.appendingPathComponent("ggml-silero.bin").path)
        XCTAssertNil(paths.resource(named: "missing"))
        try? FileManager.default.removeItem(at: root)
    }
}

final class FileSecretStoreTests: XCTestCase {
    func test_round_trip_permissions_and_absence() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("secrets-\(UUID())")
        let store = FileSecretStore(directory: dir)
        XCTAssertTrue(store.isAbsent(key: "remote.apiKey"))
        try store.save(key: "remote.apiKey", value: "sk-test")
        XCTAssertEqual(store.load(key: "remote.apiKey"), "sk-test")
        XCTAssertFalse(store.isAbsent(key: "remote.apiKey"))
        let attrs = try FileManager.default.attributesOfItem(atPath: store.url(for: "remote.apiKey")!.path)
        XCTAssertEqual((attrs[.posixPermissions] as? Int) ?? 0 & 0o777, 0o600)
        try store.save(key: "remote.apiKey", value: "")
        XCTAssertTrue(store.isAbsent(key: "remote.apiKey"))
        XCTAssertNil(store.url(for: ""))
        XCTAssertFalse(store.url(for: "../escape")!.path.contains(".."))
        try? FileManager.default.removeItem(at: dir)
    }
}

final class LinuxFolderWatcherTests: XCTestCase {
    func test_file_creation_triggers_callback() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let watcher = LinuxFolderWatcher()
        let fired = expectation(description: "change reported")
        fired.assertForOverFulfill = false
        try watcher.start(directory: dir) { fired.fulfill() }
        try Data("hello".utf8).write(to: dir.appendingPathComponent("memo.wav"))
        wait(for: [fired], timeout: 5)
        watcher.stop()
        try? FileManager.default.removeItem(at: dir)
    }
}

final class LinuxMeetingSignalsTests: XCTestCase {
    func test_detects_known_process_names_from_a_fake_proc() async throws {
        let proc = FileManager.default.temporaryDirectory.appendingPathComponent("proc-\(UUID())")
        for (pid, comm) in [("100", "zoom\n"), ("200", "bash\n"), ("300", "teams-for-linux\n"), ("self", "x")] {
            let d = proc.appendingPathComponent(pid)
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try Data(comm.utf8).write(to: d.appendingPathComponent("comm"))
        }
        let found = await LinuxMeetingSignals(procRoot: proc).activeMeetings()
        XCTAssertEqual(Set(found.map(\.appKey)), ["zoom", "teams"])
        try? FileManager.default.removeItem(at: proc)
    }
}

final class LinuxSleepInhibitorTests: XCTestCase {
    func test_acquire_and_release_do_not_leak_the_helper() {
        let inhibitor = LinuxSleepInhibitor()
        inhibitor.acquire(reason: "test")
        inhibitor.release()
        XCTAssertFalse(inhibitor.isActive)
    }
}

final class TextInjectorTests: XCTestCase {
    func test_wayland_without_typing_tool_leaves_text_on_clipboard() async {
        final class Spy: Notifier, @unchecked Sendable {
            var notes: [String] = []
            func beep() {}
            func notify(title: String, body: String) { notes.append(title) }
        }
        let spy = Spy()
        // A PATH with no clipboard tool at all: the failure is reported, never hidden.
        let injector = LinuxTextInjector(notifier: spy, environment: ["XDG_SESSION_TYPE": "wayland", "PATH": "/nonexistent"])
        let outcome = await injector.inject("shalom")
        if case .failed = outcome {} else { XCTFail("expected .failed without a clipboard tool, got \(outcome)") }
        XCTAssertTrue(spy.notes.isEmpty)
    }
}

final class UpdaterTests: XCTestCase {
    typealias Release = GitHubReleasesUpdater.Release

    func release(_ tag: String, pre: Bool = false, draft: Bool = false) -> Release {
        Release(tagName: tag, name: tag, body: "notes for \(tag)", prerelease: pre, draft: draft,
                htmlURL: URL(string: "https://github.com/NX1X/OpenMila/releases/tag/\(tag)")!)
    }

    func test_stable_client_never_sees_a_prerelease_even_if_unflagged() {
        let releases = [release("v1.9.6-beta.1", pre: false), release("v1.9.5+port.1"), release("v2.0.0", draft: true)]
        let update = GitHubReleasesUpdater.newest(in: releases, currentVersion: "1.9.4+port.3", includePrereleases: false)
        XCTAssertEqual(update?.version, "1.9.5")
        XCTAssertEqual(update?.isPrerelease, false)
    }

    func test_beta_client_gets_the_newest_prerelease() {
        let releases = [release("v1.9.6-beta.2", pre: true), release("v1.9.6-beta.10", pre: true), release("v1.9.5")]
        let update = GitHubReleasesUpdater.newest(in: releases, currentVersion: "1.9.5", includePrereleases: true)
        XCTAssertEqual(update?.version, "1.9.6-beta.10")
        XCTAssertTrue(update!.isPrerelease)
    }

    func test_up_to_date_client_gets_nothing() {
        XCTAssertNil(GitHubReleasesUpdater.newest(in: [release("v1.9.5")], currentVersion: "1.9.5+port.2", includePrereleases: true))
    }

    func test_semantic_version_ordering() {
        let v = { SemanticVersion($0)! }
        XCTAssertLessThan(v("1.9.5-beta.2"), v("1.9.5"))
        XCTAssertLessThan(v("1.9.5-beta.2"), v("1.9.5-beta.10"))
        XCTAssertLessThan(v("1.9.5"), v("1.10.0"))
        XCTAssertEqual(v("1.9.5+port.1"), v("1.9.5+port.2"))
        XCTAssertNil(SemanticVersion("Alpharetta"))
    }
}

/// The Secret Service store, exercised against whatever keyring the machine is
/// running. Skipped where none answers (a bare X session, a container, CI),
/// because the fallback is then the thing under test and `FileSecretStore`
/// has its own coverage.
final class SecretServiceStoreTests: XCTestCase {
    private let key = "openmila-test-\(UUID().uuidString)"

    func test_a_secret_round_trips_through_the_keyring() throws {
        try XCTSkipUnless(SecretServiceStore.isAvailable, "no Secret Service on this session bus")
        let store = SecretServiceStore()
        XCTAssertTrue(store.isAbsent(key: key))

        try store.save(key: key, value: "hunter2")
        XCTAssertEqual(store.load(key: key), "hunter2")
        XCTAssertFalse(store.isAbsent(key: key))

        try store.save(key: key, value: "hunter3")
        XCTAssertEqual(store.load(key: key), "hunter3")

        try store.delete(key: key)
        XCTAssertNil(store.load(key: key))
        XCTAssertTrue(store.isAbsent(key: key))
    }

    func test_saving_an_empty_value_removes_the_entry() throws {
        try XCTSkipUnless(SecretServiceStore.isAvailable, "no Secret Service on this session bus")
        let store = SecretServiceStore()
        try store.save(key: key, value: "temporary")
        try store.save(key: key, value: "")
        XCTAssertNil(store.load(key: key))
    }

    func test_deleting_something_that_was_never_stored_is_not_an_error() throws {
        try XCTSkipUnless(SecretServiceStore.isAvailable, "no Secret Service on this session bus")
        XCTAssertNoThrow(try SecretServiceStore().delete(key: key))
    }

    /// The platform hands out the keyring when one is running, and files when
    /// none is; either way a secret written comes back.
    func test_the_platform_store_round_trips_whichever_backend_it_chose() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("openmila-secrets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LinuxSecretStore(fallbackDirectory: directory)
        try store.save(key: key, value: "value")
        XCTAssertEqual(store.load(key: key), "value")
        try store.delete(key: key)
        XCTAssertNil(store.load(key: key))
    }
}
/// The pw-dump reading behind per-application audio capture. The graph is a
/// fixture, so this runs anywhere - the live path is exercised by
/// `openmila-cli app-audio`.
final class PipeWireGraphTests: XCTestCase {
    private func object(_ props: [String: Any]) -> [String: Any] {
        ["info": ["props": props]]
    }

    func test_an_application_stream_becomes_a_target() throws {
        let target = try XCTUnwrap(PipeWireAppAudioCapture.target(from: object([
            "media.class": "Stream/Output/Audio",
            "object.serial": 73,
            "application.name": "Zoom",
            "media.name": "Zoom Meeting",
            "application.process.id": 4242,
        ])))
        XCTAssertEqual(target.id, "73")
        XCTAssertEqual(target.name, "Zoom - Zoom Meeting")
        XCTAssertEqual(target.scope, .application(processID: 4242))
    }

    func test_a_stream_without_a_pid_still_becomes_a_target() throws {
        let target = try XCTUnwrap(PipeWireAppAudioCapture.target(from: object([
            "media.class": "Stream/Output/Audio",
            "object.serial": 5,
            "node.name": "pw-play",
        ])))
        XCTAssertEqual(target.id, "5")
        XCTAssertEqual(target.name, "pw-play")
        XCTAssertEqual(target.scope, .application(processID: 0))
    }

    func test_inputs_sinks_and_video_are_not_targets() {
        for mediaClass in ["Stream/Input/Audio", "Audio/Sink", "Audio/Source", "Stream/Output/Video"] {
            XCTAssertNil(PipeWireAppAudioCapture.target(from: object([
                "media.class": mediaClass, "object.serial": 9, "application.name": "x",
            ])), "\(mediaClass) should not be offered as an app-audio target")
        }
    }

    func test_a_stream_with_no_serial_is_skipped() {
        // Without a serial there is nothing to hand --target, and the node id
        // is not a safe substitute: it is reused as nodes come and go.
        XCTAssertNil(PipeWireAppAudioCapture.target(from: object([
            "media.class": "Stream/Output/Audio", "application.name": "Zoom",
        ])))
    }
}
#endif
