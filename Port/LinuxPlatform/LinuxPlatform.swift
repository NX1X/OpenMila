// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only: this module is the Linux platform layer, and SwiftPM
// builds every target in the package on every OS, including a Windows
// `swift test`.
#if os(Linux)

import AudioCapture
import Foundation
import PlatformKit
import Updater

public enum LinuxPlatform {
    public static let repository = "NX1X/OpenMila"

    /// Everything the app needs from Linux, assembled once at launch.
    public static func services(appVersion: String) -> PlatformServices {
        let paths = LinuxAppPaths()
        let notifier = LinuxNotifier()
        return PlatformServices(
            microphone: MiniaudioMicrophone(),
            appAudio: LinuxAppAudioCapture(),
            hotkeys: X11Hotkeys.isAvailable ? try? X11Hotkeys() : nil,
            textInjector: LinuxTextInjector(notifier: notifier),
            secrets: LinuxSecretStore(fallbackDirectory: paths.dataDirectory.appendingPathComponent("secrets", isDirectory: true)),
            sleep: LinuxSleepInhibitor(),
            paths: paths,
            updater: GitHubReleasesUpdater(repository: repository, currentVersion: appVersion),
            notifier: notifier,
            meetings: LinuxMeetingSignals(),
            binaryTrust: FailClosedBinaryTrust()
        )
    }
}

/// Until Linux binaries from Anthropic can be checked against a publisher
/// signature, nothing is trusted. Upstream's SecStaticCode check has no
/// Linux equivalent yet.
public struct FailClosedBinaryTrust: BinaryTrust {
    public init() {}
    public func isTrusted(executable: URL, expectedPublisher: String) -> Bool { false }
}
#endif
