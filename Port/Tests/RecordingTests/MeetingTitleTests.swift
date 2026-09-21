// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import TranscriptionCore
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

/// Which graphics device the model is handed to. The probe needs a Vulkan
/// driver, so the choice is a pure function over a device list and this tests
/// that; `openmila-cli gpu` exercises the probe on a real machine.
final class GPUSelectionTests: XCTestCase {
    typealias GPU = VulkanAvailability.GPU

    let laptop = [
        GPU(index: 0, name: "Intel UHD Graphics 770", kind: "integrated GPU"),
        GPU(index: 1, name: "NVIDIA GeForce RTX 4060 Laptop GPU", kind: "discrete GPU"),
    ]

    /// Enumeration order puts the iGPU first on most laptops, and picking the
    /// first device would quietly use it instead of the card.
    func test_a_discrete_card_wins_over_an_integrated_one() {
        XCTAssertEqual(VulkanAvailability.best(among: laptop)?.index, 1)
    }

    func test_the_users_pick_is_honoured() {
        let chosen = VulkanAvailability.select(among: laptop, preferring: "Intel UHD Graphics 770")
        XCTAssertEqual(chosen?.index, 0)
    }

    /// A card that is gone falls back instead of refusing to transcribe.
    func test_a_missing_pick_falls_back_to_the_best_present_device() {
        let chosen = VulkanAvailability.select(among: laptop, preferring: "AMD Radeon RX 7900 XTX")
        XCTAssertEqual(chosen?.index, 1)
    }

    func test_no_devices_means_no_choice() {
        XCTAssertNil(VulkanAvailability.select(among: [], preferring: "anything"))
    }

    /// Two discrete cards: the earlier one wins, so the answer is stable rather
    /// than dependent on dictionary order.
    func test_two_equal_devices_resolve_by_enumeration_order() {
        let pair = [
            GPU(index: 0, name: "NVIDIA A", kind: "discrete GPU"),
            GPU(index: 1, name: "NVIDIA B", kind: "discrete GPU"),
        ]
        XCTAssertEqual(VulkanAvailability.best(among: pair)?.name, "NVIDIA A")
    }
}
