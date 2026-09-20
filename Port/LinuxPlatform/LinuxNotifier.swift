// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only: this module is the Linux platform layer, and SwiftPM
// builds every target in the package on every OS, including a Windows
// `swift test`.
#if os(Linux)

import Foundation
import PlatformKit

/// Desktop notifications through `notify-send` (libnotify), which every
/// desktop Ubuntu ships. Upstream: `NSSound.beep()` and one-shot alerts.
public struct LinuxNotifier: Notifier {
    public init() {}

    public func beep() {
        // The terminal bell is the closest portable equivalent; desktops map
        // it to the system alert sound.
        FileHandle.standardError.write(Data([0x07]))
    }

    public func notify(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/notify-send")
        process.arguments = ["--app-name=OpenMila", title, body]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
#endif
