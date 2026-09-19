// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import CMiniaudio
import Foundation
import PlatformKit

/// Microphone capture over miniaudio: PulseAudio/PipeWire/ALSA on Linux, WASAPI
/// on Windows. On Linux, monitor sources ("Monitor of ...") appear in the same
/// device list, which is how whole-system audio is recorded there.
public struct MiniaudioMicrophone: MicrophoneCapture {
    public init() {}

    public func inputDevices() throws -> [AudioInputDevice] {
        try Self.devices(kind: OM_DEVICE_CAPTURE)
    }

    public func start(deviceID: String?) throws -> AudioCaptureSession {
        try MiniaudioSession(kind: OM_DEVICE_CAPTURE, deviceID: deviceID)
    }

    static func devices(kind: om_device_kind) throws -> [AudioInputDevice] {
        var buffer = [om_device_info](repeating: om_device_info(), count: 64)
        let count = om_list_devices(kind, &buffer, Int32(buffer.count))
        guard count >= 0 else {
            throw AudioCaptureError.noBackend(String(cString: om_result_description(count)))
        }
        return buffer.prefix(Int(count)).map { info in
            AudioInputDevice(
                id: withUnsafeBytes(of: info.id) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) },
                name: withUnsafeBytes(of: info.name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) },
                isDefault: info.is_default != 0
            )
        }
    }
}

/// Whole-system output capture through WASAPI loopback. Linux has no loopback
/// device type; pick a monitor source through `MiniaudioMicrophone` instead.
public struct MiniaudioSystemLoopback: AppAudioCapture {
    public init() {}

    public func targets() throws -> [AudioCaptureTarget] {
        #if os(Windows)
        return try MiniaudioMicrophone.devices(kind: OM_DEVICE_LOOPBACK).map {
            AudioCaptureTarget(id: $0.id, name: $0.name, scope: .wholeSystem)
        }
        #else
        return try MiniaudioMicrophone.devices(kind: OM_DEVICE_CAPTURE)
            .filter { $0.name.lowercased().hasPrefix("monitor of") }
            .map { AudioCaptureTarget(id: $0.id, name: $0.name, scope: .wholeSystem) }
        #endif
    }

    public func start(target: AudioCaptureTarget) throws -> AudioCaptureSession {
        #if os(Windows)
        return try MiniaudioSession(kind: OM_DEVICE_LOOPBACK, deviceID: target.id)
        #else
        return try MiniaudioSession(kind: OM_DEVICE_CAPTURE, deviceID: target.id)
        #endif
    }
}

/// Bridges miniaudio's audio-thread callback into an `AsyncStream`.
///
/// The callback runs on a realtime thread, so it does the minimum: copy the
/// samples and yield. `AsyncStream.Continuation.yield` is safe to call from any
/// thread and never blocks. The buffering policy bounds memory if the consumer
/// stalls: about a minute of audio, after which the OLDEST chunks are dropped,
/// matching upstream's "delay, then shed" stance on a stuck consumer.
final class MiniaudioSession: AudioCaptureSession, @unchecked Sendable {
    let samples: AsyncStream<[Float]>
    private(set) var backendName: String = ""

    private let continuation: AsyncStream<[Float]>.Continuation
    private let lock = NSLock()
    private var handle: OpaquePointer?
    private var frames = 0

    var capturedFrameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return frames
    }

    init(kind: om_device_kind, deviceID: String?) throws {
        var continuation: AsyncStream<[Float]>.Continuation!
        samples = AsyncStream(bufferingPolicy: .bufferingNewest(6_000)) { continuation = $0 }
        self.continuation = continuation

        var error: Int32 = 0
        let user = Unmanaged.passUnretained(self).toOpaque()
        let started = om_capture_start(kind, deviceID ?? "", { user, samples, count in
            guard let user, let samples, count > 0 else { return }
            let session = Unmanaged<MiniaudioSession>.fromOpaque(user).takeUnretainedValue()
            session.deliver(UnsafeBufferPointer(start: samples, count: Int(count)))
        }, user, &error)

        guard let started else {
            continuation.finish()
            throw AudioCaptureError.deviceUnavailable(String(cString: om_result_description(error)))
        }
        handle = started
        backendName = String(cString: om_capture_backend_name(started))
    }

    private func deliver(_ buffer: UnsafeBufferPointer<Float>) {
        lock.lock()
        frames += buffer.count
        lock.unlock()
        continuation.yield(Array(buffer))
    }

    func stop() {
        lock.lock()
        let active = handle
        handle = nil
        lock.unlock()
        // Joins the audio thread: after this returns, `deliver` cannot run, so
        // the unretained self pointer handed to C is never used again.
        if let active { om_capture_stop(active) }
        continuation.finish()
    }

    deinit { stop() }
}
