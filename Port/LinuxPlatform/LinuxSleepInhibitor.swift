// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only: this module is the Linux platform layer, and SwiftPM
// builds every target in the package on every OS, including a Windows
// `swift test`.
#if os(Linux)

import Foundation
import PlatformKit

/// Keeps the machine awake while recording. Upstream: `SleepGuard`
/// (IOPMAssertion).
///
/// Two helpers are tried, in order: `gnome-session-inhibit` (the desktop
/// session's own inhibitor, always granted inside a GNOME session) and
/// `systemd-inhibit` (logind, which may need a polkit agent). Each holds its
/// lock for as long as the helper process lives, so ending the helper, or the
/// app crashing, releases it.
public final class LinuxSleepInhibitor: SleepInhibitor, @unchecked Sendable {
    private let lock = NSLock()
    private var helper: Process?

    public init() {}

    public func acquire(reason: String) {
        lock.lock(); defer { lock.unlock() }
        guard helper == nil else { return }
        let candidates: [(String, [String])] = [
            ("/usr/bin/gnome-session-inhibit", ["--inhibit", "idle:suspend", "--reason", reason, "sleep", "infinity"]),
            ("/usr/bin/systemd-inhibit", ["--what=idle:sleep", "--who=OpenMila", "--mode=block",
                                          "--why=\(reason)", "sleep", "infinity"]),
        ]
        for (path, arguments) in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { continue }
            helper = process
            return
        }
    }

    public func release() {
        lock.lock(); defer { lock.unlock() }
        helper?.terminate()
        helper = nil
    }

    public var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return helper?.isRunning ?? false
    }

    deinit { release() }
}
#endif
