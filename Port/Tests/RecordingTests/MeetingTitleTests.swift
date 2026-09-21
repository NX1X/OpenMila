// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import PlatformKit
import XCTest

/// Meeting detection from window titles. Reading the titles needs a display
/// and a per-system API (`XQueryTree`, `EnumWindows`), so the matching is a
/// pure function shared by both platform layers and this tests that; the live
/// path is exercised by `openmila-cli meetings` with a window open.
final class MeetingTitleTests: XCTestCase {
    func test_a_browser_tab_in_a_meeting_is_detected() {
        let found = MeetingTitles.meetings(inTitles: [
            "Google Meet - standup",
            "Inbox (12) - Mail",
        ])
        XCTAssertEqual(found, [DetectedMeeting(appName: "Google Meet", appKey: "googleMeet")])
    }

    func test_the_meet_url_counts_too() {
        let found = MeetingTitles.meetings(inTitles: ["meet.google.com/abc-defg-hij - Chromium"])
        XCTAssertEqual(found.first?.appKey, "googleMeet")
    }

    func test_the_same_meeting_in_two_windows_is_reported_once() {
        let found = MeetingTitles.meetings(inTitles: [
            "Google Meet - standup", "Google Meet - standup",
        ])
        XCTAssertEqual(found.count, 1)
    }

    func test_ordinary_windows_are_not_meetings() {
        let found = MeetingTitles.meetings(inTitles: [
            "OpenMila", "Terminal", "meeting notes.md - Obsidian", "",
        ])
        XCTAssertTrue(found.isEmpty, "found \(found)")
    }

    /// A pure Wayland session sees no other client's windows, so the title
    /// signal contributes nothing and the process signal stands alone.
    func test_no_titles_means_no_title_detections() {
        XCTAssertTrue(MeetingTitles.meetings(inTitles: []).isEmpty)
    }

    func test_a_proton_meet_tab_is_detected() {
        XCTAssertEqual(MeetingTitles.meetings(inTitles: ["Proton Meet - weekly"]),
                       [DetectedMeeting(appName: "Proton Meet", appKey: "protonMeet")])
        XCTAssertEqual(MeetingTitles.meetings(inTitles: ["meet.proton.me/abc - Firefox"]).first?.appKey,
                       "protonMeet")
    }

    /// Proton Mail's own tab is not a call, and neither is the word "meeting"
    /// in a document name: a needle has to be specific enough that the prompt
    /// does not fire on ordinary browsing.
    func test_other_proton_windows_are_not_meetings() {
        XCTAssertTrue(MeetingTitles.meetings(inTitles: [
            "Proton Mail", "mail.proton.me - Inbox", "proton drive",
        ]).isEmpty)
    }
}
