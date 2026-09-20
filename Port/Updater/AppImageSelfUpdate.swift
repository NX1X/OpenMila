// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import Crypto
import Foundation
import PlatformKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Replaces a running AppImage with a newer one from a GitHub release, which
/// is what Sparkle does for upstream's `.app`.
///
/// Only an AppImage can be updated this way. A `.deb` belongs to the package
/// manager and a Windows install to its own installer, so both are reported
/// back as `.manual` and the user finishes from the release page.
///
/// The download is refused unless the release also publishes a checksum for
/// it. An unverifiable binary that replaces the running application is exactly
/// the thing an update mechanism must not do, so no checksum means no install,
/// not "install anyway".
public struct AppImageSelfUpdate: Sendable {
    public enum Error: Swift.Error, LocalizedError, Equatable {
        case noAsset
        case noChecksum(String)
        case checksumMismatch(String)
        case notReplaceable(String)

        public var errorDescription: String? {
            switch self {
            case .noAsset:
                return "This release has no AppImage for your machine."
            case .noChecksum(let name):
                return "The release publishes no checksum for \(name), so it was not installed."
            case .checksumMismatch(let name):
                return "The download of \(name) did not match its published checksum and was discarded."
            case .notReplaceable(let detail):
                return "This installation cannot update itself. \(detail)"
            }
        }
    }

    /// The AppImage this process is running from, as AppImageKit sets it.
    /// Absent for a `.deb` install, a development build or a Windows build.
    public static var runningAppImage: URL? {
        guard let path = ProcessInfo.processInfo.environment["APPIMAGE"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private let fetch: @Sendable (URL) async throws -> Data
    private let runningImage: URL?

    /// `runningImage` is injectable so tests can point at a file they own;
    /// nothing else passes it.
    public init(fetch: @escaping @Sendable (URL) async throws -> Data = GitHubReleasesUpdater.download,
                runningImage: URL? = AppImageSelfUpdate.runningAppImage) {
        self.fetch = fetch
        self.runningImage = runningImage
    }

    public func install(_ update: AvailableUpdate, architecture: String = currentArchitecture) async throws -> UpdateInstallOutcome {
        guard let target = runningImage else {
            return .manual(update.downloadPage)
        }
        guard let asset = Self.appImageAsset(in: update.assets, architecture: architecture) else {
            throw Error.noAsset
        }
        let expected = try await expectedChecksum(for: asset, in: update.assets)
        let payload = try await fetch(asset.url)
        let actual = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw Error.checksumMismatch(asset.name) }
        try Self.replace(target, with: payload)
        return .installed(restartRequired: true)
    }

    // MARK: Choosing what to download

    /// The release's AppImage for this architecture. Release files are named
    /// `OpenMila-<version>-<arch>.AppImage`.
    static func appImageAsset(in assets: [UpdateAsset], architecture: String) -> UpdateAsset? {
        let appImages = assets.filter { $0.name.hasSuffix(".AppImage") }
        return appImages.first { $0.name.contains(architecture) } ?? (appImages.count == 1 ? appImages.first : nil)
    }

    /// The checksum for `asset`, from a per-file `<name>.sha256` or from a
    /// combined `SHA256SUMS`, whichever the release publishes.
    private func expectedChecksum(for asset: UpdateAsset, in assets: [UpdateAsset]) async throws -> String {
        if let perFile = assets.first(where: { $0.name == asset.name + ".sha256" }) {
            let text = String(decoding: try await fetch(perFile.url), as: UTF8.self)
            if let value = Self.checksum(for: asset.name, inSums: text) ?? Self.loneChecksum(in: text) {
                return value
            }
        }
        if let sums = assets.first(where: { $0.name.uppercased().hasPrefix("SHA256SUMS") }) {
            let text = String(decoding: try await fetch(sums.url), as: UTF8.self)
            if let value = Self.checksum(for: asset.name, inSums: text) { return value }
        }
        throw Error.noChecksum(asset.name)
    }

    /// One line of `sha256sum` output: "<hex>  <name>", with the name
    /// optionally carrying a directory or a leading "*" for binary mode.
    static func checksum(for name: String, inSums text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let candidate = String(parts[0]).lowercased()
            let named = parts.dropFirst().joined(separator: " ")
            let file = named.hasPrefix("*") ? String(named.dropFirst()) : named
            guard Self.isHexDigest(candidate), (file as NSString).lastPathComponent == name else { continue }
            return candidate
        }
        return nil
    }

    /// A `<name>.sha256` that holds only the digest.
    private static func loneChecksum(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return isHexDigest(trimmed) ? trimmed : nil
    }

    static func isHexDigest(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy { $0.isHexDigit }
    }

    // MARK: Putting it in place

    /// Writes the new build beside the old one and renames it over the top, so
    /// a failure part-way through leaves the working AppImage untouched.
    /// Renaming a running AppImage is safe: the kernel keeps the open image
    /// alive until the process exits.
    static func replace(_ target: URL, with payload: Data) throws {
        let directory = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw Error.notReplaceable("\(directory.path) is not writable by you.")
        }
        let staging = directory.appendingPathComponent(".\(target.lastPathComponent).new-\(UUID().uuidString)")
        do {
            try payload.write(to: staging, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staging)
            // replaceItemAt carries the REPLACED file's attributes over, so
            // the executable bit is set again here: an AppImage that is not
            // executable cannot be launched, and the old file's permissions
            // are not a promise.
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    public static var currentArchitecture: String {
        #if arch(arm64)
        return "aarch64"
        #else
        return "x86_64"
        #endif
    }
}
