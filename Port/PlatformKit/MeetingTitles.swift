// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// The window-title half of meeting detection, shared by both platform layers
// so a meeting that is recognised on one system is recognised on the other.
// Pure: no display, no system call, so it is testable everywhere.

import Foundation

/// Meetings that live in a browser tab rather than in an application.
///
/// Upstream finds these in the window title of Chrome, Safari, Arc or Island,
/// because a tab has no process of its own to look for. The browser does not
/// matter here, only what the tab calls itself.
///
/// Where the titles come from is per-system, and that is where the systems
/// differ: Windows hands any application the titles of every top-level window
/// (`EnumWindows`), X11 the same (`XQueryTree`), and a pure Wayland session
/// none at all, by design - a client cannot see another client's windows.
/// So a tab meeting is detected on Windows and on X11/XWayland, and on a
/// Wayland session only an application with its own process is.
public enum MeetingTitles {
    public struct Pattern: Sendable {
        /// Lowercased substring looked for in a window title.
        public let needle: String
        public let appName: String
        /// Upstream `MeetingApp` raw value where one exists. "protonMeet" has
        /// no upstream case yet, so a saved Proton Meet recording gets the
        /// generic source badge; detection and the prompt do not depend on it.
        public let appKey: String
    }

    /// Two needles per service where both forms appear: a browser shows the
    /// page title ("Proton Meet"), and some show the host ("meet.proton.me").
    public static let patterns: [Pattern] = [
        Pattern(needle: "meet.google.com", appName: "Google Meet", appKey: "googleMeet"),
        Pattern(needle: "google meet", appName: "Google Meet", appKey: "googleMeet"),
        Pattern(needle: "meet.proton.me", appName: "Proton Meet", appKey: "protonMeet"),
        Pattern(needle: "proton meet", appName: "Proton Meet", appKey: "protonMeet"),
        Pattern(needle: "zoom meeting", appName: "Zoom", appKey: "zoom"),
        Pattern(needle: "microsoft teams", appName: "Microsoft Teams", appKey: "teams"),
    ]

    /// The meetings a list of window titles implies, in the order the patterns
    /// declare them and without duplicates.
    public static func meetings(inTitles titles: [String]) -> [DetectedMeeting] {
        var found: [DetectedMeeting] = []
        for title in titles {
            let haystack = title.lowercased()
            for pattern in patterns where haystack.contains(pattern.needle) {
                let meeting = DetectedMeeting(appName: pattern.appName, appKey: pattern.appKey)
                if !found.contains(meeting) { found.append(meeting) }
            }
        }
        return found
    }
}
