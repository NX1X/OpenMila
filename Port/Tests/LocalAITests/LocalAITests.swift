// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import Foundation
import XCTest
@testable import LocalAI

/// The parts of local AI that need no network and no runtime: what is offered,
/// how the pin is shaped, and how a streamed pull is read.
final class LocalModelCatalogueTests: XCTestCase {
    /// Every offered model names its publisher and licence, so the choice is
    /// an informed one, and the recommendation is the first entry.
    func test_every_model_states_publisher_and_licence() {
        for model in LocalModel.catalogue {
            XCTAssertFalse(model.publisher.isEmpty, model.name)
            XCTAssertFalse(model.licence.isEmpty, model.name)
            XCTAssertGreaterThan(model.sizeGB, 0, model.name)
            XCTAssertGreaterThan(model.minimumRAMGB, 0, model.name)
        }
        XCTAssertEqual(LocalModel.recommended.name, "mistral")
    }

    /// The maintainer's rule: Western, open-licensed models only. Pinned here
    /// so a catalogue edit that breaks it fails a test rather than a review.
    func test_the_catalogue_is_western_and_open() {
        let allowedPublishers = ["Mistral AI", "Allen Institute", "Google", "Meta", "Hugging Face", "NVIDIA"]
        for model in LocalModel.catalogue {
            XCTAssertTrue(allowedPublishers.contains { model.publisher.contains($0) },
                          "\(model.name) is published by \(model.publisher)")
            XCTAssertFalse(model.name.lowercased().contains("qwen"), model.name)
            XCTAssertFalse(model.name.lowercased().contains("deepseek"), model.name)
        }
    }

    func test_names_are_unique_and_pullable() {
        let names = LocalModel.catalogue.map(\.name)
        XCTAssertEqual(names.count, Set(names).count)
        for name in names {
            XCTAssertFalse(name.contains(" "), name)
        }
    }
}

final class OllamaReleasePinTests: XCTestCase {
    /// On the systems the port ships for, the pin is a full 64-hex digest and
    /// an https URL on the vendor's release page for that exact version.
    func test_the_pin_is_complete_where_it_applies() throws {
        guard let release = OllamaRelease.pinned else { throw XCTSkip("no pinned runtime for this system") }
        XCTAssertEqual(release.sha256.count, 64)
        XCTAssertTrue(release.sha256.allSatisfy { $0.isHexDigit })
        XCTAssertEqual(release.url.scheme, "https")
        XCTAssertTrue(release.url.absoluteString.contains("/v\(release.version)/"))
        XCTAssertTrue(release.url.lastPathComponent == release.archiveName)
    }
}

final class ManagedOllamaLayoutTests: XCTestCase {
    /// Everything lives under the cache, in one directory, so removing it
    /// removes all of it and an uninstall purge has one path to name.
    func test_everything_lives_under_one_cache_directory() {
        let cache = URL(fileURLWithPath: "/tmp/openmila-cache-test", isDirectory: true)
        let managed = ManagedOllama(cacheDirectory: cache)
        XCTAssertEqual(managed.root.path, "/tmp/openmila-cache-test/local-ai")
        XCTAssertTrue(managed.runtimeDirectory.path.hasPrefix(managed.root.path))
        XCTAssertTrue(managed.modelsDirectory.path.hasPrefix(managed.root.path))
        XCTAssertTrue(managed.executable.path.hasPrefix(managed.runtimeDirectory.path))
    }

    /// Files alone do not make a trusted runtime: without the stamp written
    /// after a verified unpack, nothing there is run.
    func test_an_unstamped_runtime_is_not_trusted() throws {
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmila-localai-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        let managed = ManagedOllama(cacheDirectory: cache)
        try FileManager.default.createDirectory(at: managed.executable.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: managed.executable.path, contents: Data("not a binary".utf8))
        XCTAssertFalse(managed.isRuntimeInstalled)
    }

    func test_sha256_of_a_file_matches_the_known_answer() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("openmila-sha-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try "abc".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try ManagedOllama.sha256Hex(of: file),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
