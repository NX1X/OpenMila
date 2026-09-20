// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import CMiniaudio
import Foundation

/// Plays a recording through the default output. Upstream: `AVPlayer` in the
/// detail view, with the 1.9.5 speed control.
///
/// Rate changes go through the WSOLA time stretcher in `om_stretch.c`, so a
/// voice keeps its pitch at every speed, as upstream's AVAudioUnitTimePitch
/// does. `StretchTests` pins both halves of that: the duration scales and the
/// frequency does not move.
public final class MiniaudioPlayer: @unchecked Sendable {
    public enum Error: Swift.Error, LocalizedError {
        case openFailed(String)
        public var errorDescription: String? {
            if case .openFailed(let d) = self { return "Could not open the audio file. \(d)" }
            return nil
        }
    }

    private let handle: OpaquePointer
    private let lock = NSLock()

    public init(url: URL) throws {
        var error: Int32 = 0
        guard let handle = om_player_open(url.path, &error) else {
            throw Error.openFailed(String(cString: om_result_description(error)))
        }
        self.handle = handle
    }

    public var duration: TimeInterval { lock.lock(); defer { lock.unlock() }; return om_player_length(handle) }
    public var position: TimeInterval { lock.lock(); defer { lock.unlock() }; return om_player_position(handle) }
    public var isPlaying: Bool { lock.lock(); defer { lock.unlock() }; return om_player_is_playing(handle) != 0 }

    public func play() { lock.lock(); defer { lock.unlock() }; om_player_play(handle) }
    public func pause() { lock.lock(); defer { lock.unlock() }; om_player_pause(handle) }
    public func seek(to seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; om_player_seek(handle, seconds) }

    /// 0.5 to 2.0, in the quarter steps upstream offers.
    public func setRate(_ rate: Double) { lock.lock(); defer { lock.unlock() }; om_player_set_rate(handle, min(2, max(0.5, rate))) }

    deinit { om_player_close(handle) }
}
