// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

#if os(Windows)
import AudioCapture
import Foundation
import PlatformKit
import Updater

public enum WindowsPlatform {
    public static let repository = "NX1X/OpenMila"

    /// Everything the app needs from Windows, assembled once at launch.
    public static func services(appVersion: String) -> PlatformServices {
        let paths = WindowsAppPaths()
        let notifier = WindowsNotifier()
        return PlatformServices(
            microphone: MiniaudioMicrophone(),
            appAudio: WindowsAppAudioCapture(),
            hotkeys: WindowsHotkeys(),
            textInjector: WindowsTextInjector(notifier: notifier),
            secrets: WindowsSecretStore(directory: paths.dataDirectory.appendingPathComponent("secrets", isDirectory: true)),
            sleep: WindowsSleepInhibitor(),
            paths: paths,
            updater: GitHubReleasesUpdater(repository: repository, currentVersion: appVersion),
            notifier: notifier,
            meetings: WindowsMeetingSignals(),
            binaryTrust: WindowsBinaryTrust()
        )
    }
}
#endif
