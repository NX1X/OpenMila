// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import Foundation
import PlatformKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Update checks against a GitHub repository's releases. Upstream: Sparkle's
/// appcast. The release's prerelease flag is the beta channel: a client that
/// has not opted in never sees one, mirroring upstream's `shouldProceedWithUpdate`
/// guard that refuses a pre-release even if a feed mislabels it.
public struct GitHubReleasesUpdater: Updater {
    public struct Release: Decodable, Equatable {
        public let tagName: String
        public let name: String?
        public let body: String?
        public let prerelease: Bool
        public let draft: Bool
        public let htmlURL: URL
        public let assets: [Asset]

        public struct Asset: Decodable, Equatable {
            public let name: String
            public let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name, browserDownloadURL = "browser_download_url"
            }

            public init(name: String, browserDownloadURL: URL) {
                self.name = name
                self.browserDownloadURL = browserDownloadURL
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", name, body, prerelease, draft, htmlURL = "html_url", assets
        }

        public init(tagName: String, name: String? = nil, body: String? = nil,
                    prerelease: Bool = false, draft: Bool = false, htmlURL: URL,
                    assets: [Asset] = []) {
            self.tagName = tagName
            self.name = name
            self.body = body
            self.prerelease = prerelease
            self.draft = draft
            self.htmlURL = htmlURL
            self.assets = assets
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tagName = try container.decode(String.self, forKey: .tagName)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            body = try container.decodeIfPresent(String.self, forKey: .body)
            prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
            draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
            htmlURL = try container.decode(URL.self, forKey: .htmlURL)
            assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        }
    }

    public let repository: String
    public let currentVersion: String
    private let fetch: @Sendable (URL) async throws -> Data

    public init(repository: String, currentVersion: String,
                fetch: @escaping @Sendable (URL) async throws -> Data = GitHubReleasesUpdater.download) {
        self.repository = repository
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    public func check(includePrereleases: Bool) async throws -> AvailableUpdate? {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20")!
        let releases = try JSONDecoder().decode([Release].self, from: try await fetch(url))
        return Self.newest(in: releases, currentVersion: currentVersion, includePrereleases: includePrereleases)
    }

    /// Pure selection, for tests: newest non-draft release that is newer than
    /// the current version, skipping pre-releases unless opted in. A version
    /// string that looks like a pre-release is refused without opt-in even if
    /// the release is not flagged, the same defence upstream keeps client-side.
    public static func newest(in releases: [Release], currentVersion: String,
                              includePrereleases: Bool) -> AvailableUpdate? {
        let current = SemanticVersion(currentVersion)
        let candidates = releases
            .filter { !$0.draft }
            .filter { includePrereleases || (!$0.prerelease && !SemanticVersion.isPrerelease($0.tagName)) }
            .compactMap { release -> (SemanticVersion, Release)? in
                guard let v = SemanticVersion(release.tagName) else { return nil }
                return (v, release)
            }
            .filter { current == nil || $0.0 > current! }
            .sorted { $0.0 > $1.0 }
        guard let (version, release) = candidates.first else { return nil }
        return AvailableUpdate(version: version.description,
                               isPrerelease: release.prerelease || SemanticVersion.isPrerelease(release.tagName),
                               releaseNotesMarkdown: release.body ?? "",
                               downloadPage: release.htmlURL,
                               assets: release.assets.map { UpdateAsset(name: $0.name, url: $0.browserDownloadURL) })
    }

    /// Replaces this build where it can: an AppImage rewrites itself after a
    /// checksum check, anything else hands the user the release page.
    public func install(_ update: AvailableUpdate) async throws -> UpdateInstallOutcome {
        try await AppImageSelfUpdate(fetch: fetch).install(update)
    }

    public static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OpenMila", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// `1.9.5`, `v1.9.5-beta.2`, `1.9.5+port.1`. Pre-release identifiers order
/// below the release they precede; build metadata is ignored for ordering.
public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int, minor: Int, patch: Int
    public let prerelease: [String]
    public let build: String?

    public init?(_ text: String) {
        var s = text.hasPrefix("v") ? String(text.dropFirst()) : text
        if let plus = s.firstIndex(of: "+") { build = String(s[s.index(after: plus)...]); s = String(s[..<plus]) } else { build = nil }
        var pre: [String] = []
        if let dash = s.firstIndex(of: "-") { pre = s[s.index(after: dash)...].split(separator: ".").map(String.init); s = String(s[..<dash]) }
        let parts = s.split(separator: ".").map { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        major = parts[0]!; minor = parts[1]!; patch = parts[2]!
        prerelease = pre
    }

    public static func isPrerelease(_ text: String) -> Bool {
        SemanticVersion(text).map { !$0.prerelease.isEmpty } ?? false
    }

    public var description: String {
        var s = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty { s += "-" + prerelease.joined(separator: ".") }
        return s
    }

    /// Semver says build metadata does not affect precedence. OpenMila's own
    /// versions are `<upstream>+port.N`, so two port releases of the same
    /// upstream version differ ONLY in build metadata, and ignoring it would
    /// make every port release look equal to the last - the updater would
    /// never offer one. The port therefore orders by build metadata as the
    /// final tiebreaker, numerically where the identifiers are numbers.
    static func buildOrder(_ lhs: String?, _ rhs: String?) -> Int {
        switch (lhs, rhs) {
        case (nil, nil): return 0
        // A build with metadata is the later one: 1.9.5 then 1.9.5+port.1.
        case (nil, _?): return -1
        case (_?, nil): return 1
        case let (left?, right?):
            let a = left.split(separator: ".").map(String.init)
            let b = right.split(separator: ".").map(String.init)
            for (x, y) in zip(a, b) where x != y {
                if let xi = Int(x), let yi = Int(y) { return xi < yi ? -1 : 1 }
                return x < y ? -1 : 1
            }
            if a.count == b.count { return 0 }
            return a.count < b.count ? -1 : 1
        }
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) == (rhs.major, rhs.minor, rhs.patch)
            && lhs.prerelease == rhs.prerelease
            && buildOrder(lhs.build, rhs.build) == 0
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return buildOrder(lhs.build, rhs.build) < 0
        case (false, true): return true
        case (true, false): return false
        case (false, false):
            for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
                switch (Int(a), Int(b)) {
                case let (x?, y?): return x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a < b
                }
            }
            if lhs.prerelease.count != rhs.prerelease.count {
                return lhs.prerelease.count < rhs.prerelease.count
            }
            return buildOrder(lhs.build, rhs.build) < 0
        }
    }
}
