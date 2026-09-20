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

    /// Global shortcuts, by whatever route this session allows.
    ///
    /// X11 lets a client grab a combination for itself, which is immediate and
    /// needs no dialog, so it is preferred when an X display is there (that
    /// includes XWayland, where the grab only reaches X clients). A pure
    /// Wayland session has no such mechanism at all: the compositor owns
    /// input, and the GlobalShortcuts portal is the only way, at the cost of
    /// one confirmation dialog the first time.
    static func hotkeys() -> GlobalHotkeys? {
        if X11Hotkeys.isAvailable, let x11 = try? X11Hotkeys() { return x11 }
        if let portal = PortalHotkeys() { return portal }
        return nil
    }

    /// Everything the app needs from Linux, assembled once at launch.
    public static func services(appVersion: String) -> PlatformServices {
        let paths = LinuxAppPaths()
        let notifier = LinuxNotifier()
        return PlatformServices(
            microphone: MiniaudioMicrophone(),
            appAudio: LinuxAppAudioCapture(),
            hotkeys: Self.hotkeys(),
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
