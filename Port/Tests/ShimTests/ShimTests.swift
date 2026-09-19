// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// These tests import the Apple module names exactly as upstream's sources do.
// If they compile and pass, upstream files using the same APIs build off macOS.

import Combine
import CryptoKit
import Foundation
import MilaKit
import OSLog
@testable import OpenMilaLogging
import os
import TranscriptionCore
import XCTest

private let testLog = Logger(subsystem: "io.github.nx1x.openmila.tests", category: "ShimTests")

/// Shape of every upstream settings object: ObservableObject + @Published.
private final class SampleSettings: ObservableObject {
    @Published var enabled = false
    @Published var name = "initial"
}

final class CombineShimTests: XCTestCase {
    func test_published_property_notifies_objectWillChange() {
        let settings = SampleSettings()
        var changes = 0
        let cancellable = settings.objectWillChange.sink { _ in changes += 1 }
        settings.enabled = true
        settings.name = "renamed"
        XCTAssertEqual(changes, 2)
        cancellable.cancel()
    }

    func test_projected_publisher_dropFirst_and_sink() {
        let settings = SampleSettings()
        var seen: [String] = []
        var bag = Set<AnyCancellable>()
        settings.$name.dropFirst().sink { seen.append($0) }.store(in: &bag)
        settings.name = "a"
        settings.name = "b"
        XCTAssertEqual(seen, ["a", "b"])
    }

    func test_receive_on_main_queue_delivers() {
        let settings = SampleSettings()
        let delivered = expectation(description: "value delivered on the main queue")
        var bag = Set<AnyCancellable>()
        settings.$enabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { value in
                XCTAssertTrue(value)
                XCTAssertTrue(Thread.isMainThread)
                delivered.fulfill()
            }
            .store(in: &bag)
        settings.enabled = true
        wait(for: [delivered], timeout: 2)
    }

    func test_assign_to_published() {
        final class Mirror: ObservableObject { @Published var copy = "" }
        let source = SampleSettings()
        let mirror = Mirror()
        source.$name.assign(to: &mirror.$copy)
        source.name = "mirrored"
        XCTAssertEqual(mirror.copy, "mirrored")
    }
}

final class LoggerShimTests: XCTestCase {
    func test_public_value_is_rendered() {
        let message: OSLogMessage = "frames=\(42, privacy: .public)"
        XCTAssertEqual(message.text, "frames=42")
    }

    func test_private_value_is_redacted_by_default() {
        let title = "Acme Corp quarterly review"
        let message: OSLogMessage = "saved \(title, privacy: .private)"
        let text = message.text
        XCTAssertFalse(text.contains("Acme"), "user content must not reach a log line")
        XCTAssertEqual(text, "saved <private>")
    }

    func test_bare_string_is_private_and_bare_number_is_public() {
        let path = "/home/user/Client X"
        let message: OSLogMessage = "path=\(path) count=\(3)"
        let text = message.text
        XCTAssertEqual(text, "path=<private> count=3")
    }

    func test_every_level_upstream_uses_is_callable() {
        testLog.log("log \(1, privacy: .public)")
        testLog.notice("notice")
        testLog.error("error \("x", privacy: .private)")
        testLog.debug("debug")
        os.Logger(subsystem: "s", category: "c").info("module-qualified form used in upstream")
    }

    func test_unfair_lock_guards_state() {
        let counter = OSAllocatedUnfairLock(initialState: 0)
        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            counter.withLock { $0 += 1 }
        }
        XCTAssertEqual(counter.withLock { $0 }, 1_000)
    }
}

final class CryptoKitShimTests: XCTestCase {
    /// Same call shape as ModelManager.verifySHA256.
    func test_streaming_sha256_matches_known_digest() {
        var hasher = SHA256()
        hasher.update(data: Data("abc".utf8))
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

final class UpstreamPackagesTests: XCTestCase {
    func test_upstream_packages_link_from_the_root_manifest() {
        XCTAssertEqual(WhisperAudioFormat.sampleRate, 16_000)
        XCTAssertEqual(WERCalculator.calculate(reference: "shalom olam", hypothesis: "shalom olam"), 0)
        XCTAssertEqual(TranscriptFormatter.joinedFullText(segments: [StoredSegmentProbe(speaker: nil, text: "shalom")]), "shalom")
    }
}

private struct StoredSegmentProbe: SpeakerTextSegment {
    let speaker: String?
    let text: String
}

final class LogBootstrapTests: XCTestCase {
    func test_file_sink_rotates_and_keeps_bounded_history() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("openmila-log-\(UUID())")
        let sink = RotatingFileSink(directory: dir, baseName: "t", maxBytes: 200, keep: 2)
        for i in 0..<100 { sink.write("line \(i) padding padding padding padding") }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(names, ["t.1.log", "t.2.log", "t.log"])
        try? FileManager.default.removeItem(at: dir)
    }

    func test_level_parsing_defaults_to_info() {
        XCTAssertEqual(OpenMilaLog.level(from: nil), .info)
        XCTAssertEqual(OpenMilaLog.level(from: "DEBUG"), .debug)
        XCTAssertEqual(OpenMilaLog.level(from: "nonsense"), .info)
    }
}
