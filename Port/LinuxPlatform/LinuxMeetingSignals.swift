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
/// Three signals, because no one of them covers every session. A native
/// application (Zoom, Teams) has a process to find, which works everywhere. A
/// meeting in a browser tab (Google Meet, Proton Meet) has no process of its
/// own, so it has to be found by window title, and where titles come from
/// depends on the session:
///
/// - **X11 or XWayland**: `XQueryTree`, the way upstream does it.
/// - **Pure Wayland**: the display protocol refuses, by design, so titles come
///   from the accessibility bus instead (`ATSPIWindowTitles`). Firefox and
///   Chromium both publish their windows there. It needs the desktop's
///   accessibility support switched on, and says so when it is not.
///
/// Both title readers are tried, in that order, and the first that names
/// anything wins. Neither is required: with neither, native applications are
/// still detected.
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
                titles: @escaping () -> [String] = LinuxMeetingSignals.windowTitles) {
        self.procRoot = procRoot
        self.titles = titles
    }

    /// Both readers, unioned, because neither is a superset of the other.
    ///
    /// The tempting rule - "X11 first, accessibility bus only when X11 is
    /// empty" - is wrong on exactly the session this exists for. A GNOME
    /// Wayland session runs XWayland, so `XQueryTree` answers with a handful of
    /// window titles (GNOME Shell, mutter's frames, whatever ibus owns) while
    /// showing nothing of a Wayland-native Firefox. Non-empty is therefore not
    /// the same as complete, and a first-wins rule would skip the accessibility
    /// bus forever on the session that needs it.
    public static func windowTitles() -> [String] {
        var titles = X11WindowTitles.all()
        guard isWaylandSession else { return titles }
        titles.append(contentsOf: accessibilityTitles())
        return titles
    }

    static var isWaylandSession: Bool {
        let environment = ProcessInfo.processInfo.environment
        if let display = environment["WAYLAND_DISPLAY"], !display.isEmpty { return true }
        return environment["XDG_SESSION_TYPE"]?.lowercased() == "wayland"
    }

    /// The accessibility walk is tens of blocking D-Bus calls, and meeting
    /// detection polls, so the answer is cached briefly. A meeting that starts
    /// during the cache window is noticed on the next poll, which is the same
    /// granularity the poll itself has.
    static let accessibilityCacheSeconds: TimeInterval = 5
    nonisolated(unsafe) private static var cachedAccessibilityTitles: (at: Date, titles: [String])?
    private static let cacheLock = NSLock()

    static func accessibilityTitles() -> [String] {
        cacheLock.lock()
        if let cached = cachedAccessibilityTitles,
           Date().timeIntervalSince(cached.at) < accessibilityCacheSeconds {
            cacheLock.unlock()
            return cached.titles
        }
        cacheLock.unlock()
        let titles = ATSPIWindowTitles.all()
        cacheLock.lock()
        cachedAccessibilityTitles = (at: Date(), titles: titles)
        cacheLock.unlock()
        return titles
    }

    /// Where titles can be read on this session, for Settings and the CLI to
    /// explain a gap rather than leave the user guessing.
    public static var titleSourceDescription: String {
        let x11 = X11WindowTitles.all().count
        guard isWaylandSession else {
            return x11 > 0
                ? "window titles come from X11 (\(x11) visible)"
                : "no window titles: no X display answered"
        }
        let fromX11 = x11 > 0 ? "X11 or XWayland shows \(x11)" : "X11 shows none"
        switch ATSPIWindowTitles.status {
        case .ready:
            return "\(fromX11); the accessibility bus shows \(accessibilityTitles().count)"
        case .accessibilityDisabled:
            return """
                \(fromX11); a Wayland-native window is invisible to it, and the accessibility bus \
                is off, so a meeting in a browser tab cannot be seen. Turn it on with: \
                gsettings set org.gnome.desktop.interface toolkit-accessibility true
                """
        case .unavailable(let reason):
            return "\(fromX11); no accessibility bus either (\(reason))"
        }
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
