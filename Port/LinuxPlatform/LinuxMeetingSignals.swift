// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only: this module is the Linux platform layer, and SwiftPM
// builds every target in the package on every OS, including a Windows
// `swift test`.
#if os(Linux)

import Foundation
import PlatformKit

/// Detects running meeting apps.
///
/// Two signals, because one is not enough. A native application (Zoom, Teams)
/// has a process to find, which works on every session. A meeting in a browser
/// tab (Google Meet) has no process of its own, and upstream finds it in the
/// window title: that is possible on X11 and XWayland, and impossible on a
/// pure Wayland session, where a client cannot see another client's windows by
/// design. So Meet is detected where the session allows it, and the port says
/// plainly that it is not detected where it does not.
public struct LinuxMeetingSignals: MeetingSignals {
    /// Lowercased `comm` names to the upstream `MeetingApp` key.
    static let knownProcesses: [(comm: String, appName: String, appKey: String)] = [
        ("zoom", "Zoom", "zoom"),
        ("zoomlinux", "Zoom", "zoom"),
        ("teams", "Microsoft Teams", "teams"),
        ("teams-for-linux", "Microsoft Teams", "teams"),
    ]

    private let procRoot: URL
    private let titles: () -> [String]

    public init(procRoot: URL = URL(fileURLWithPath: "/proc"),
                titles: @escaping () -> [String] = X11WindowTitles.all) {
        self.procRoot = procRoot
        self.titles = titles
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
        // Shared with the Windows layer, so both systems recognise the same
        // tab meetings from the titles their own APIs can see.
        for meeting in MeetingTitles.meetings(inTitles: titles()) where !found.contains(meeting) {
            found.append(meeting)
        }
        return found
    }
}
#endif
