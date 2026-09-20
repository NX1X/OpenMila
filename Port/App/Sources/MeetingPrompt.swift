// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port of `MeetingPromptCoordinator` (Mila/Views/MeetingPromptOverlay.swift)
// over PlatformKit's `MeetingSignals`: polls for meeting apps while the
// feature is on, offers to record when one appears, and offers to stop when
// it goes away during a recording. Upstream keys on Core Audio process taps;
// here the signal is the process table, so only native apps are seen.

import Combine
import Foundation
import PlatformKit
import Recording
@testable import Mila

@MainActor
final class MeetingPrompt: ObservableObject {
    enum Offer: Equatable { case start(DetectedMeeting), stop(DetectedMeeting) }

    @Published private(set) var offer: Offer?

    private let signals: MeetingSignals
    private let settings: MeetingDetectionSettings
    private let notifier: Notifier
    private let session: RecordingSession
    private var active: Set<DetectedMeeting> = []
    private var dismissed: Set<DetectedMeeting> = []
    private var task: Task<Void, Never>?

    init(signals: MeetingSignals, settings: MeetingDetectionSettings, notifier: Notifier, session: RecordingSession) {
        self.signals = signals
        self.settings = settings
        self.notifier = notifier
        self.session = session
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    func dismiss() {
        if case .start(let meeting) = offer { dismissed.insert(meeting) }
        offer = nil
    }

    func poll() async {
        guard settings.enabled else { offer = nil; return }
        let now = Set(await signals.activeMeetings())
        let started = now.subtracting(active).subtracting(dismissed)
        let ended = active.subtracting(now)
        active = now
        dismissed = dismissed.intersection(now)
        if let meeting = started.first, session.state == .idle {
            offer = .start(meeting)
            notifier.notify(title: "\(meeting.appName) started", body: "Record this meeting with \(AppIdentity.name)?")
        } else if let meeting = ended.first, session.state != .idle {
            offer = .stop(meeting)
            notifier.notify(title: "\(meeting.appName) ended", body: "Stop the recording?")
        } else if case .start(let m) = offer, !now.contains(m) {
            offer = nil
        }
    }
}
