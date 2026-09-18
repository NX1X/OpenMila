// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Security-scoped bookmarks are a macOS sandbox mechanism. Upstream persists a
// user-chosen folder (recordings directory, Obsidian vault) as a bookmark and
// brackets access with start/stopAccessingSecurityScopedResource.
//
// Linux and Windows have no sandbox to negotiate with, so here a "bookmark" is
// the folder's absolute path as UTF-8 and the access calls succeed without
// doing anything. Upstream's persistence code then runs unchanged, including
// its "folder vanished" handling, which checks the resolved path itself.

import Foundation

extension URL {
    public struct BookmarkCreationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let withSecurityScope = BookmarkCreationOptions(rawValue: 1 << 11)
        public static let securityScopeAllowOnlyReadAccess = BookmarkCreationOptions(rawValue: 1 << 12)
        public static let minimalBookmark = BookmarkCreationOptions(rawValue: 1 << 9)
    }

    public struct BookmarkResolutionOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let withSecurityScope = BookmarkResolutionOptions(rawValue: 1 << 10)
        public static let withoutUI = BookmarkResolutionOptions(rawValue: 1 << 8)
        public static let withoutMounting = BookmarkResolutionOptions(rawValue: 1 << 9)
    }

    private static let bookmarkPrefix = "openmila-path:"

    public func bookmarkData(
        options: BookmarkCreationOptions = [],
        includingResourceValuesForKeys keys: Set<URLResourceKey>? = nil,
        relativeTo url: URL? = nil
    ) throws -> Data {
        guard isFileURL else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
        return Data((Self.bookmarkPrefix + standardizedFileURL.path).utf8)
    }

    public init(
        resolvingBookmarkData data: Data,
        options: BookmarkResolutionOptions = [],
        relativeTo url: URL? = nil,
        bookmarkDataIsStale: inout Bool
    ) throws {
        // Anything that is not one of our own blobs is a macOS bookmark from a
        // settings file copied across machines. It cannot be resolved here;
        // failing makes upstream drop it and fall back to the default folder.
        guard let text = String(data: data, encoding: .utf8),
              text.hasPrefix(Self.bookmarkPrefix) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let path = String(text.dropFirst(Self.bookmarkPrefix.count))
        guard path.hasPrefix("/") || path.contains(":") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        bookmarkDataIsStale = false
        self = URL(fileURLWithPath: path)
    }

    /// No sandbox to enter. Returns `true` so callers that pair this with
    /// `stopAccessingSecurityScopedResource()` keep their bookkeeping balanced.
    public func startAccessingSecurityScopedResource() -> Bool { true }

    public func stopAccessingSecurityScopedResource() {}
}
