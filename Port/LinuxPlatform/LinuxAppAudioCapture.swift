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
        return Self.disambiguated(applications) + monitors
    }

    /// Two streams from the same application (two browser tabs, say) carry the
    /// same name, and the picker shows names, so a repeated one gets its
    /// stream number appended. Unique names are left exactly as they are.
    static func disambiguated(_ targets: [AudioCaptureTarget]) -> [AudioCaptureTarget] {
        var counts: [String: Int] = [:]
        for target in targets { counts[target.name, default: 0] += 1 }
        var seen: [String: Int] = [:]
        return targets.map { target in
            guard counts[target.name, default: 0] > 1 else { return target }
            let index = seen[target.name, default: 0] + 1
            seen[target.name] = index
            return AudioCaptureTarget(id: target.id, name: "\(target.name) (\(index))", scope: target.scope)
        }
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
