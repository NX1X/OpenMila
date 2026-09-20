// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twins of `CaptureStallDetector` and `RebuildThrottle`, which upstream
// keeps inside `Mila/Audio/MicrophoneRecorder.swift`. That file is
// AVFoundation-bound and excluded from this build, so the policy it contains
// was not compiled at all off macOS: a microphone that went quiet mid-meeting
// stayed quiet, silently, which is the failure upstream wrote these to catch.
//
// Copied rather than reimplemented, so the behaviour is upstream's and a
// change there is a diff here. Both are pure value types with an injected
// clock, so they test exactly and without sleeping. See CHANGES.md.

import Foundation

/// Watches a cumulative frame count and reports when it stops moving.
public struct CaptureStallDetector: Sendable {
    /// How long the frame count may sit still before this calls it a stall.
    public let timeout: TimeInterval
    private var lastFrames: Int?
    private var armedAt: Date?

    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    /// Feed the current cumulative frame count. Returns true once the count
    /// has not moved for `timeout`.
    ///
    /// The first call arms the clock rather than reporting a stall, so a
    /// device that comes up but never delivers its first buffer also trips
    /// the detector once `timeout` has passed.
    public mutating func observe(frames: Int, now: Date) -> Bool {
        defer { lastFrames = frames }
        guard let last = lastFrames, let armedAt else {
            self.armedAt = now
            return false
        }
        if frames > last {
            self.armedAt = now
            return false
        }
        return now.timeIntervalSince(armedAt) >= timeout
    }

    /// Re-arm after a recovery attempt, so the next stall is timed from the
    /// restart rather than from the last buffer the dead device delivered.
    public mutating func reset() {
        lastFrames = nil
        armedAt = nil
    }
}

/// Minimum interval plus exponential backoff for restart attempts.
///
/// Upstream's reason applies here too: a restart can itself provoke whatever
/// prompted the restart, and without a gate the two feed each other fast
/// enough that capture never lives long enough to deliver a buffer.
public struct RebuildThrottle: Sendable {
    public let minimumInterval: TimeInterval
    public let maximumInterval: TimeInterval

    private var lastAllowedAt: Date?
    public private(set) var streak = 0

    /// Idle time that ends a burst. Twice the ceiling rather than the ceiling
    /// itself: a saturated burst arrives exactly one `maximumInterval` apart,
    /// and treating that as quiet would reset the ladder every tick.
    public var quietPeriod: TimeInterval { maximumInterval * 2 }

    public init(minimumInterval: TimeInterval, maximumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
        self.maximumInterval = max(minimumInterval, maximumInterval)
    }

    /// How long after the last allowed restart the next one may happen. Zero
    /// before the first: the first trouble in a session is always acted on.
    public var currentInterval: TimeInterval {
        guard streak > 0 else { return 0 }
        let scaled = minimumInterval * pow(2, Double(streak - 1))
        return min(scaled, maximumInterval)
    }

    /// Whether a restart may proceed at `now`. Mutating: an allowed restart
    /// starts the clock for the next one and lengthens the backoff.
    public mutating func allow(now: Date) -> Bool {
        if let last = lastAllowedAt {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < currentInterval { return false }
            if elapsed >= quietPeriod { streak = 0 }
        }
        lastAllowedAt = now
        streak += 1
        return true
    }
}
