// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// The install half of the updater. The check half is covered by
// MilaTests/UpdaterPrereleaseGuardTests and the selection tests beside it.

import Crypto
import Foundation
import PlatformKit
import XCTest
@testable import Updater

final class SelfUpdateTests: XCTestCase {
    private let page = URL(string: "https://github.com/NX1X/OpenMila/releases/tag/v1.9.6")!

    private func asset(_ name: String) -> UpdateAsset {
        UpdateAsset(name: name, url: URL(string: "https://example.invalid/\(name)")!)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Choosing the file

    func test_the_appimage_for_this_architecture_is_chosen() {
        let assets = [asset("OpenMila-1.9.6-x86_64.AppImage"),
                      asset("OpenMila-1.9.6-aarch64.AppImage"),
                      asset("openmila_1.9.6_amd64.deb")]
        XCTAssertEqual(AppImageSelfUpdate.appImageAsset(in: assets, architecture: "aarch64")?.name,
                       "OpenMila-1.9.6-aarch64.AppImage")
    }

    func test_a_release_without_an_appimage_chooses_nothing() {
        let assets = [asset("openmila_1.9.6_amd64.deb"), asset("OpenMila-1.9.6-win64.zip")]
        XCTAssertNil(AppImageSelfUpdate.appImageAsset(in: assets, architecture: "x86_64"))
    }

    func test_an_appimage_for_another_architecture_is_not_offered() {
        let assets = [asset("OpenMila-1.9.6-x86_64.AppImage"), asset("OpenMila-1.9.6-aarch64.AppImage")]
        XCTAssertNil(AppImageSelfUpdate.appImageAsset(in: assets, architecture: "riscv64"))
    }

    // MARK: Reading checksums

    func test_a_checksum_is_read_from_a_sums_file() {
        let sums = """
        0000000000000000000000000000000000000000000000000000000000000000  openmila_1.9.6_amd64.deb
        1111111111111111111111111111111111111111111111111111111111111111 *OpenMila-1.9.6-x86_64.AppImage
        """
        XCTAssertEqual(AppImageSelfUpdate.checksum(for: "OpenMila-1.9.6-x86_64.AppImage", inSums: sums),
                       "1111111111111111111111111111111111111111111111111111111111111111")
    }

    func test_a_sums_file_without_the_file_yields_nothing() {
        let sums = "2222222222222222222222222222222222222222222222222222222222222222  something-else.AppImage"
        XCTAssertNil(AppImageSelfUpdate.checksum(for: "OpenMila-1.9.6-x86_64.AppImage", inSums: sums))
    }

    // MARK: Installing

    /// Serves the release's files from memory, and records what was asked for.
    /// `runningImage` stands in for the AppImage this process would be: the
    /// real value comes from an environment variable, which Windows' CRT has no
    /// portable setter for, so it is injected rather than set.
    private func updater(files: [String: Data], runningImage: URL?) -> (AppImageSelfUpdate, () -> [String]) {
        let requested = Recorder()
        let installer = AppImageSelfUpdate(fetch: { url in
            let name = url.lastPathComponent
            requested.add(name)
            guard let data = files[name] else { throw URLError(.fileDoesNotExist) }
            return data
        }, runningImage: runningImage)
        return (installer, { requested.names })
    }

    /// A Sendable box, because the fetch closure is @Sendable.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        func add(_ name: String) { lock.lock(); storage.append(name); lock.unlock() }
        var names: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    private func withRunningAppImage(_ body: (URL) async throws -> Void) async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("openmila-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("OpenMila-1.9.5-x86_64.AppImage")
        try Data("old build".utf8).write(to: image)
        try await body(image)
    }

    func test_a_verified_appimage_replaces_the_running_one() async throws {
        try await withRunningAppImage { image in
            let payload = Data("new build".utf8)
            let name = "OpenMila-1.9.6-x86_64.AppImage"
            let (installer, _) = updater(files: [
                name: payload,
                "SHA256SUMS": Data("\(digest(payload))  \(name)\n".utf8),
            ], runningImage: image)
            let update = AvailableUpdate(version: "1.9.6", isPrerelease: false, releaseNotesMarkdown: "",
                                         downloadPage: page, assets: [asset(name), asset("SHA256SUMS")])

            let outcome = try await installer.install(update, architecture: "x86_64")

            XCTAssertEqual(outcome, .installed(restartRequired: true))
            XCTAssertEqual(try Data(contentsOf: image), payload)
            let permissions = try FileManager.default.attributesOfItem(atPath: image.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.int16Value, 0o755)
        }
    }

    func test_a_download_that_fails_its_checksum_is_discarded() async throws {
        try await withRunningAppImage { image in
            let name = "OpenMila-1.9.6-x86_64.AppImage"
            let (installer, _) = updater(files: [
                name: Data("tampered".utf8),
                "SHA256SUMS": Data("\(digest(Data("expected".utf8)))  \(name)\n".utf8),
            ], runningImage: image)
            let update = AvailableUpdate(version: "1.9.6", isPrerelease: false, releaseNotesMarkdown: "",
                                         downloadPage: page, assets: [asset(name), asset("SHA256SUMS")])

            await XCTAssertThrowsErrorAsync(try await installer.install(update, architecture: "x86_64")) { error in
                XCTAssertEqual(error as? AppImageSelfUpdate.Error, .checksumMismatch(name))
            }
            XCTAssertEqual(try Data(contentsOf: image), Data("old build".utf8), "the running build must survive")
        }
    }

    func test_a_release_without_a_checksum_installs_nothing() async throws {
        try await withRunningAppImage { image in
            let name = "OpenMila-1.9.6-x86_64.AppImage"
            let (installer, requested) = updater(files: [name: Data("new build".utf8)], runningImage: image)
            let update = AvailableUpdate(version: "1.9.6", isPrerelease: false, releaseNotesMarkdown: "",
                                         downloadPage: page, assets: [asset(name)])

            await XCTAssertThrowsErrorAsync(try await installer.install(update, architecture: "x86_64")) { error in
                XCTAssertEqual(error as? AppImageSelfUpdate.Error, .noChecksum(name))
            }
            XCTAssertEqual(try Data(contentsOf: image), Data("old build".utf8))
            XCTAssertFalse(requested().contains(name), "an unverifiable build should not even be downloaded")
        }
    }

    func test_a_build_that_is_not_an_appimage_sends_the_user_to_the_release_page() async throws {
        let (installer, _) = updater(files: [:], runningImage: nil)
        let update = AvailableUpdate(version: "1.9.6", isPrerelease: false, releaseNotesMarkdown: "",
                                     downloadPage: page, assets: [asset("openmila_1.9.6_amd64.deb")])
        let outcome = try await installer.install(update, architecture: "x86_64")
        XCTAssertEqual(outcome, .manual(page))
    }
}

/// XCTAssertThrowsError has no async form in corelibs XCTest.
func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T,
                                  file: StaticString = #filePath, line: UInt = #line,
                                  _ handler: (Error) -> Void) async {
    do {
        _ = try await expression()
        XCTFail("expected an error", file: file, line: line)
    } catch {
        handler(error)
    }
}

/// Version ordering, which decides whether an update is offered at all.
/// OpenMila's versions are `<upstream>+port.N`, so the port number lives in
/// the build metadata that semver says to ignore - and ignoring it would make
/// every port release of one upstream version look identical.
final class VersionOrderTests: XCTestCase {
    private func version(_ text: String) throws -> SemanticVersion {
        try XCTUnwrap(SemanticVersion(text))
    }

    func test_a_later_port_of_the_same_upstream_version_is_newer() throws {
        XCTAssertTrue(try version("1.9.5+port.0") < version("1.9.5+port.1"))
        XCTAssertFalse(try version("1.9.5+port.1") < version("1.9.5+port.0"))
        XCTAssertNotEqual(try version("1.9.5+port.0"), try version("1.9.5+port.1"))
    }

    func test_port_numbers_order_as_numbers_not_as_text() throws {
        XCTAssertTrue(try version("1.9.5+port.9") < version("1.9.5+port.10"))
    }

    func test_upstream_version_still_wins_over_the_port_number() throws {
        XCTAssertTrue(try version("1.9.5+port.7") < version("1.9.6+port.0"))
    }

    func test_a_prerelease_of_an_upstream_version_precedes_its_release() throws {
        XCTAssertTrue(try version("1.9.5-beta.2+port.0") < version("1.9.5+port.0"))
        XCTAssertTrue(try version("1.9.5-beta.2+port.0") < version("1.9.5-beta.2+port.1"))
        XCTAssertTrue(SemanticVersion.isPrerelease("v1.9.5-beta.2+port.0"))
        XCTAssertFalse(SemanticVersion.isPrerelease("v1.9.5+port.0"))
    }

    func test_the_same_version_is_equal_to_itself() throws {
        XCTAssertEqual(try version("1.9.5-beta.2+port.0"), try version("v1.9.5-beta.2+port.0"))
    }
}
