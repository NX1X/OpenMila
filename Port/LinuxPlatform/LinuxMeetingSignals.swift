// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import Foundation
import PlatformKit

/// Detects running meeting apps by process name. Upstream keys on audio
/// process taps and window titles; Wayland exposes neither globally, so the
/// process table is the signal available everywhere. Browser-hosted Meet is
/// not detectable this way and is left to a later, X11-only title scan.
public struct LinuxMeetingSignals: MeetingSignals {
    /// Lowercased `comm` names to the upstream `MeetingApp` key.
    static let knownProcesses: [(comm: String, appName: String, appKey: String)] = [
        ("zoom", "Zoom", "zoom"),
        ("zoomlinux", "Zoom", "zoom"),
        ("teams", "Microsoft Teams", "teams"),
        ("teams-for-linux", "Microsoft Teams", "teams"),
    ]

    private let procRoot: URL

    public init(procRoot: URL = URL(fileURLWithPath: "/proc")) {
        self.procRoot = procRoot
    }

    public func activeMeetings() async -> [DetectedMeeting] {
        var found: [DetectedMeeting] = []
        guard let pids = try? FileManager.default.contentsOfDirectory(atPath: procRoot.path) else { return [] }
        for pid in pids where Int(pid) != nil {
            let commURL = procRoot.appendingPathComponent(pid).appendingPathComponent("comm")
            guard let comm = try? String(contentsOf: commURL, encoding: .utf8) else { continue }
            let name = comm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let match = Self.knownProcesses.first(where: { $0.comm == name }) {
                let meeting = DetectedMeeting(appName: match.appName, appKey: match.appKey)
                if !found.contains(meeting) { found.append(meeting) }
            }
        }
        return found
    }
}
