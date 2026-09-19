// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import Foundation

/// Audio travels through OpenMila as mono Float32 at 16 kHz, the format
/// whisper.cpp consumes. Capture backends convert at the device; nothing
/// downstream resamples.
public enum PlatformAudioFormat {
    public static let sampleRate: Double = 16_000
    public static let channelCount = 1
}

public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// Opaque backend identifier, valid for this process only.
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

public enum AudioCaptureError: Error, LocalizedError, Equatable {
    case noBackend(String)
    case deviceUnavailable(String)
    case alreadyRunning

    public var errorDescription: String? {
        switch self {
        case .noBackend(let detail): return "No audio system is available. \(detail)"
        case .deviceUnavailable(let detail): return "The audio device could not be opened. \(detail)"
        case .alreadyRunning: return "Capture is already running."
        }
    }
}

/// One live capture. Chunks arrive in order on `samples`; the stream finishes
/// when `stop()` is called or the device goes away.
public protocol AudioCaptureSession: AnyObject, Sendable {
    var samples: AsyncStream<[Float]> { get }
    var backendName: String { get }
    /// Total frames delivered so far. Upstream's stall watchdog reads the
    /// equivalent counter to tell a dead input from a quiet one.
    var capturedFrameCount: Int { get }
    func stop()
}

/// Microphone capture: upstream's `MicrophoneRecorder` + `AudioDeviceManager`.
public protocol MicrophoneCapture: Sendable {
    func inputDevices() throws -> [AudioInputDevice]
    /// `deviceID` nil selects the system default input.
    func start(deviceID: String?) throws -> AudioCaptureSession
}

/// The source of "the other side of the meeting": upstream's
/// `SystemAudioRecorder` (ScreenCaptureKit, per application).
public struct AudioCaptureTarget: Identifiable, Hashable, Sendable {
    public enum Scope: Sendable, Hashable {
        /// Everything the machine plays.
        case wholeSystem
        /// One application's output, by process id.
        case application(processID: Int32)
    }
    public let id: String
    public let name: String
    public let scope: Scope

    public init(id: String, name: String, scope: Scope) {
        self.id = id
        self.name = name
        self.scope = scope
    }
}

public protocol AppAudioCapture: Sendable {
    func targets() throws -> [AudioCaptureTarget]
    func start(target: AudioCaptureTarget) throws -> AudioCaptureSession
}
