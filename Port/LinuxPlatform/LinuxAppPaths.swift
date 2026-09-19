// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import Foundation
import PlatformKit

/// XDG base directories, with the app's own resources beside the executable
/// (which is where Bundle.main looks off macOS) or in a `share/openmila`
/// sibling of the `bin` directory for packaged installs.
public struct LinuxAppPaths: AppPaths {
    public let dataDirectory: URL
    public let cacheDirectory: URL
    public let logDirectory: URL
    private let resourceDirectories: [URL]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                executable: URL = URL(fileURLWithPath: CommandLine.arguments.first ?? "").resolvingSymlinksInPath()) {
        func xdg(_ key: String, _ fallback: String) -> URL {
            if let value = environment[key], value.hasPrefix("/") { return URL(fileURLWithPath: value) }
            return home.appendingPathComponent(fallback)
        }
        // "Mila", not "openmila": upstream's cross-process contracts (the MCP
        // helper's store pointer, mcp-access.json, the LLM sandbox, the managed
        // Claude install) all resolve `<app support>/Mila` by name in code the
        // port reuses unchanged. One data root keeps them consistent.
        dataDirectory = xdg("XDG_DATA_HOME", ".local/share").appendingPathComponent("Mila", isDirectory: true)
        cacheDirectory = xdg("XDG_CACHE_HOME", ".cache").appendingPathComponent("openmila", isDirectory: true)
        logDirectory = xdg("XDG_STATE_HOME", ".local/state").appendingPathComponent("openmila/logs", isDirectory: true)
        let binDir = executable.deletingLastPathComponent()
        var candidates = [binDir]
        if let override = environment["OPENMILA_RESOURCES"] { candidates.insert(URL(fileURLWithPath: override), at: 0) }
        candidates.append(binDir.deletingLastPathComponent().appendingPathComponent("share/openmila"))
        resourceDirectories = candidates
    }

    public func resource(named name: String) -> URL? {
        for dir in resourceDirectories {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
