// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only.
#if os(Linux)

import AudioCapture
import Foundation
import PlatformKit

/// What the app offers as "the other side of the meeting": every running
/// application that is playing audio (through PipeWire), plus the whole-system
/// monitors, which are the fallback when PipeWire's tools are absent or the
/// user would rather record everything.
///
/// Upstream lists applications only, because ScreenCaptureKit has no
/// whole-system option; keeping both here costs one extra row and is the only
/// thing that works on a system without `pipewire-bin`.
public struct LinuxAppAudioCapture: AppAudioCapture {
    private let perApplication = PipeWireAppAudioCapture()
    private let wholeSystem = MiniaudioSystemLoopback()

    public init() {}

    public func targets() throws -> [AudioCaptureTarget] {
        // Applications first: that is what a meeting recording wants, and
        // upstream's picker shows applications at the top too.
        let applications = (try? perApplication.targets()) ?? []
        let monitors = (try? wholeSystem.targets()) ?? []
        if applications.isEmpty && monitors.isEmpty {
            // Report the reason rather than an empty list.
            return try wholeSystem.targets()
        }
        return applications + monitors
    }

    public func start(target: AudioCaptureTarget) throws -> AudioCaptureSession {
        switch target.scope {
        case .application:
            return try perApplication.start(target: target)
        case .wholeSystem:
            return try wholeSystem.start(target: target)
        }
    }
}
#endif
