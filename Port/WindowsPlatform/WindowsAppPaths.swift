// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import Foundation
import PlatformKit

/// Windows locations. The data directory is Foundation's application-support
/// directory plus "Mila", the same expression upstream's shared code uses to
/// find the MCP store pointer and the other cross-process files, so both sides
/// agree without special cases.
public struct WindowsAppPaths: AppPaths {
    public let dataDirectory: URL
    public let cacheDirectory: URL
    public let logDirectory: URL
    private let resourceDirectories: [URL]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                executable: URL = URL(fileURLWithPath: CommandLine.arguments.first ?? "").resolvingSymlinksInPath()) {
        let fm = FileManager.default
        let roaming = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("AppData/Roaming")
        let local = environment["LOCALAPPDATA"].map { URL(fileURLWithPath: $0) }
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("AppData/Local")
        dataDirectory = roaming.appendingPathComponent("Mila", isDirectory: true)
        cacheDirectory = local.appendingPathComponent("OpenMila/cache", isDirectory: true)
        logDirectory = local.appendingPathComponent("OpenMila/logs", isDirectory: true)

        let binDir = executable.deletingLastPathComponent()
        var candidates = [binDir]
        if let override = environment["OPENMILA_RESOURCES"] { candidates.insert(URL(fileURLWithPath: override), at: 0) }
        candidates.append(binDir.appendingPathComponent("Resources", isDirectory: true))
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
