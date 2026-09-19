// swift-tools-version: 5.10
// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// OpenMila build manifest for Linux and Windows.
//
// macOS keeps building from upstream's `project.yml` + Xcode. This manifest is
// the port: it consumes upstream's source tree in place (no moved files) and
// adds the platform layers under `Port/`.
//
// The shim targets below are literally named after Apple-only modules
// (`Combine`, `OSLog`, `os`, `CryptoKit`, `Accelerate`, `SwiftUI`). Off macOS no system module of that
// name exists, so upstream's `import Combine` lines compile unchanged against
// the open-source replacement.
//
// HAZARD: a shim's name also turns `canImport(<name>)` true for every package
// in the build. Only shim a name no dependency tests for. `Darwin` is tested by
// almost everything and must never be shimmed. OpenCombine tests `Combine`, which
// is safe only because the shim depends on OpenCombine and so builds after it; if
// OpenCombine is ever rebuilt with a stale Combine module on disk, clean first
// (`swift package clean`). They must never be declared on macOS, where
// they would shadow the real frameworks.
import PackageDescription

#if os(macOS)
#error("Build OpenMila's macOS variant from upstream's project.yml; this manifest targets Linux and Windows.")
#endif

let package = Package(
    name: "OpenMila",
    products: [
        .library(name: "OpenMilaShims", targets: ["Combine", "OSLog", "os", "CryptoKit", "Accelerate"]),
        // Everything the app package (Port/App) links: the upstream core plus
        // the port layers. The app lives in its own package so that the root's
        // `swift test` never has to build the UI toolkit.
        .library(name: "OpenMilaCore", targets: [
            "Mila", "Combine", "OSLog", "os", "CryptoKit", "OpenMilaLogging",
            "PlatformKit", "AudioCapture", "Recording", "Updater",
        ]),
        .library(name: "OpenMilaLinux", targets: ["LinuxPlatform"]),
    ],
    dependencies: [
        .package(path: "Packages/MilaKit"),
        .package(path: "Packages/TranscriptionCore"),
        // Exact pins. Bumps are deliberate, one PR each, after a 14-day cooldown.
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", exact: "0.14.0"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.15.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
    ],
    targets: [
        // MARK: Shims (Apple module names, open-source implementations)
        .target(
            name: "Combine",
            dependencies: [
                .product(name: "OpenCombine", package: "OpenCombine"),
                .product(name: "OpenCombineDispatch", package: "OpenCombine"),
                .product(name: "OpenCombineFoundation", package: "OpenCombine"),
            ],
            path: "Port/Shims/Combine"
        ),
        .target(
            name: "OpenMilaLogging",
            dependencies: [.product(name: "Logging", package: "swift-log")],
            path: "Port/Shims/OpenMilaLogging"
        ),
        .target(name: "OSLog", dependencies: ["OpenMilaLogging"], path: "Port/Shims/OSLog"),
        .target(name: "os", dependencies: ["OpenMilaLogging"], path: "Port/Shims/os"),
        .target(name: "Accelerate", path: "Port/Shims/Accelerate"),
        .target(name: "SwiftUI", path: "Port/Shims/SwiftUI"),
        // pty prototypes glibc hides from Swift. Not a shim: the name is ours.
        .target(name: "COpenMilaPosix", path: "Port/COpenMilaPosix"),
        .target(
            name: "CryptoKit",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")],
            path: "Port/Shims/CryptoKit"
        ),

        // MARK: Platform seam and audio
        .target(name: "PlatformKit", path: "Port/PlatformKit"),
        .target(
            name: "CMiniaudio",
            path: "Port/CMiniaudio",
            cSettings: [.define("MA_NO_RUNTIME_LINKING", .when(platforms: [.windows]))],
            linkerSettings: [
                .linkedLibrary("dl", .when(platforms: [.linux])),
                .linkedLibrary("m", .when(platforms: [.linux])),
                .linkedLibrary("pthread", .when(platforms: [.linux])),
            ]
        ),
        .target(name: "AudioCapture", dependencies: ["CMiniaudio", "PlatformKit"], path: "Port/AudioCapture"),
        .target(name: "Recording", dependencies: ["PlatformKit"], path: "Port/Recording"),
        .target(name: "Updater", dependencies: ["PlatformKit"], path: "Port/Updater"),
        .systemLibrary(name: "CX11", path: "Port/CX11", pkgConfig: "x11", providers: [.apt(["libx11-dev"])]),
        .target(
            name: "LinuxPlatform",
            dependencies: ["PlatformKit", "AudioCapture", "Updater", "CX11"],
            path: "Port/LinuxPlatform"
        ),
        .testTarget(
            name: "LinuxPlatformTests",
            dependencies: ["LinuxPlatform", "Updater", "PlatformKit"],
            path: "Port/Tests/LinuxPlatformTests"
        ),
        .testTarget(
            name: "RecordingTests",
            dependencies: ["Recording", "PlatformKit", .product(name: "TranscriptionCore", package: "TranscriptionCore")],
            path: "Port/Tests/RecordingTests"
        ),
        .executableTarget(
            name: "openmila-cli",
            dependencies: [
                "AudioCapture", "PlatformKit", "OpenMilaLogging", "Recording", "Updater",
                .target(name: "LinuxPlatform", condition: .when(platforms: [.linux])),
                .product(name: "TranscriptionCore", package: "TranscriptionCore"),
            ],
            path: "Port/CLI"
        ),

        // MARK: Upstream core, consumed in place
        //
        // Everything under Mila/ that is not tied to an Apple UI or capture
        // framework. The module keeps upstream's name so `@testable import Mila`
        // in upstream's tests compiles unchanged. Excluded files have a port twin
        // under Port/ or are Apple-only.
        .target(
            name: "Mila",
            dependencies: [
                "Combine", "OSLog", "os", "CryptoKit", "Accelerate", "SwiftUI", "COpenMilaPosix",
                .product(name: "MilaKit", package: "MilaKit"),
                .product(name: "TranscriptionCore", package: "TranscriptionCore"),
            ],
            // Rooted at the repository so the target can take upstream's tree
            // and the port twins together; `sources` keeps it to those two.
            path: ".",
            exclude: [
                // Everything at the root that is not this target's business.
                "Packages", "MilaTests", "MilaUITests", "MilaMCP", "Port/Shims", "Port/Tests",
                "Port/PlatformKit", "Port/CMiniaudio", "Port/AudioCapture", "Port/CLI", "Port/COpenMilaPosix", "Port/Spikes", "ci",
                "Port/Recording", "Port/Tests/RecordingTests", "Port/Updater", "Port/CX11", "Port/LinuxPlatform", "Port/Tests/LinuxPlatformTests", "Port/App", "docs",
                "docs", "docs-internal", "scripts", "docker", "skills", "bugbot-rules",
                "RELEASE_NOTES", "Makefile", "project.yml", "README.md", "CHANGES.md",
                "CLAUDE.md", "CODE_OF_CONDUCT.md", "CONTRIBUTING.md", "SECURITY.md",
                "THIRD_PARTY_NOTICES.md", "LICENSE", "NOTICE",
                // Apple-only or replaced by a twin under Port/.
                "Mila/Views", "Mila/Resources", "Mila/Assets.xcassets", "Mila/VoiceMemos",
                "Mila/App",
                "Mila/Audio/MicrophoneRecorder.swift", "Mila/Audio/SystemAudioRecorder.swift",
                "Mila/Audio/AudioDeviceManager.swift", "Mila/Audio/InputLevelMonitor.swift",
                "Mila/Audio/MeetingDetector.swift", "Mila/Audio/SleepGuard.swift",
                "Mila/Audio/AudioCompressor.swift", "Mila/Audio/RecordingSession.swift",
                "Mila/Audio/AudioUtilities.swift", "Mila/Audio/FileTranscriber.swift",
                "Mila/Dictation",
                "Mila/Actions/QuickActionsController.swift", "Mila/Actions/DiagnosticReporter.swift",
                "Mila/Models/KeychainHelper.swift", "Mila/Models/SystemCapabilities.swift",
            ],
            sources: ["Mila", "Port/CoreTwins"],
            // -enable-testing: upstream's types are internal (Mila is one Xcode
            // module); the port's app is a second module and reaches them via
            // `@testable import Mila`. Kept on in every configuration.
            swiftSettings: [.unsafeFlags(["-swift-version", "5", "-enable-testing"])]
        ),

        // MARK: Tests
        // Upstream's own unit tests, run against the core on Linux and Windows.
        // Excluded files test Apple-bound code (capture, hotkeys, views, the
        // app scene); the list shrinks as port twins for those layers land.
        .testTarget(
            name: "MilaTests",
            dependencies: [
                "Mila", "Combine", "OSLog", "os", "CryptoKit",
                .product(name: "MilaKit", package: "MilaKit"),
                .product(name: "TranscriptionCore", package: "TranscriptionCore"),
            ],
            // Rooted at the repository for the same reason as the core: it takes
            // upstream's tests in place plus the port's TestSupport twin.
            path: ".",
            exclude: [
                "Packages", "Mila", "MilaUITests", "MilaMCP", "Port/Shims", "Port/CoreTwins",
                "Port/PlatformKit", "Port/CMiniaudio", "Port/AudioCapture", "Port/CLI", "Port/COpenMilaPosix", "Port/Spikes", "ci",
                "Port/Recording", "Port/Tests/RecordingTests", "Port/Updater", "Port/CX11", "Port/LinuxPlatform", "Port/Tests/LinuxPlatformTests", "Port/App", "docs",
                "Port/Tests/ShimTests", "docs", "docs-internal", "scripts", "docker", "skills",
                "bugbot-rules", "RELEASE_NOTES", "Makefile", "project.yml", "README.md",
                "CHANGES.md", "CLAUDE.md", "CODE_OF_CONDUCT.md", "CONTRIBUTING.md",
                "SECURITY.md", "THIRD_PARTY_NOTICES.md", "LICENSE", "NOTICE",
                // Tests of Apple-bound code; the list shrinks as twins land.
                // Fixture manifests carry only darwin keys; the port asks for linux/win32 keys.
                "MilaTests/ClaudeBinaryInstallerTests.swift", "MilaTests/ClaudeManagedInstallTests.swift",
                "MilaTests/AIOverviewSummaryTests.swift",
                "MilaTests/AISettingsKeyCompatibilityTests.swift",
                "MilaTests/ClaudeSetupSettingsTests.swift",
                "MilaTests/LiveAIBulletsTests.swift",
                "MilaTests/LiveTranscriptSidecarWriterTests.swift",
                "MilaTests/ModelManagerTests.swift",
                "MilaTests/TranscriptExporterTests.swift",
                "MilaTests/TranscriptFollowTests.swift",
                "MilaTests/RecordingDetailPlaceholderTests.swift",
                "MilaTests/RecordingStoreTests.swift",
                "MilaTests/RecordingTests.swift",
                "MilaTests/SpeakerDirectoryTests.swift",
                "MilaTests/AppSceneChurnTests.swift",
                "MilaTests/AudioConvertTests.swift",
                "MilaTests/AudioDeviceManagerTests.swift",
                "MilaTests/AudioMeterTests.swift",
                "MilaTests/CrossRecordingVoiceIsolationTests.swift",
                "MilaTests/DiagnosticReporterTests.swift",
                "MilaTests/DictationControllerTests.swift",
                "MilaTests/DictationPasteboardTests.swift",
                "MilaTests/FileTranscriberTests.swift",
                "MilaTests/HotkeySettingsTests.swift",
                "MilaTests/LaunchRecoveryTests.swift",
                "MilaTests/LiveAIDeletedLineSessionTests.swift",
                "MilaTests/LiveAIThrottleTests.swift",
                "MilaTests/LiveSidecarHandoffOrderingTests.swift",
                "MilaTests/LiveSpeakerNamingTests.swift",
                "MilaTests/LiveTranscriberSpeakerLabelTests.swift",
                "MilaTests/LiveTranscriptLineDeleteTests.swift",
                "MilaTests/MeetingAppTests.swift",
                "MilaTests/MeetingDetectorAppsTests.swift",
                "MilaTests/MeetingDetectorBrowserDetectionTests.swift",
                "MilaTests/MeetingStopPromptTests.swift",
                "MilaTests/MicrophoneRecorderTests.swift",
                "MilaTests/ObsidianExportSequencingTests.swift",
                "MilaTests/ObsidianExporterTests.swift",
                "MilaTests/OfflineVoiceEmbedderTests.swift",
                "MilaTests/PostRecordingCoordinatorSendTests.swift",
                "MilaTests/PromptUndoTests.swift",
                "MilaTests/QuickActionsControllerTests.swift",
                "MilaTests/RecognisedSpeakerAssignerTests.swift",
                "MilaTests/RecognisedSpeakerMergeTests.swift",
                "MilaTests/RecordingSessionMetersTests.swift",
                "MilaTests/RecordingSessionPauseTests.swift",
                "MilaTests/RecordingSummarizerTests.swift",
                "MilaTests/RemoteTranscriptionE2ETests.swift",
                "MilaTests/ScrollGesturePolicyTests.swift",
                "MilaTests/SeedAnchorAutoNameAgreementTests.swift",
                "MilaTests/SpeakerColorTests.swift",
                "MilaTests/SpeakerCorrectionActionsTests.swift",
                "MilaTests/StoreLocationPointerFailureTests.swift",
                "MilaTests/SystemAudioRestartPolicyTests.swift",
                "MilaTests/TestSupport.swift",
                "MilaTests/UpdaterPrereleaseGuardTests.swift",
                "MilaTests/VoiceMemosImporterPlanTests.swift",
                "MilaTests/VoiceMemosLibraryTests.swift",
                "MilaTests/VoiceRecognitionGateTests.swift",
                "MilaTests/WAVHeaderRepairTests.swift",
                "MilaTests/WindowChromeExemptionTests.swift",
            ],
            sources: ["MilaTests", "Port/Tests/MilaTestsSupport"],
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        ),
        .testTarget(
            name: "ShimTests",
            dependencies: [
                "Combine", "OSLog", "os", "CryptoKit", "OpenMilaLogging",
                .product(name: "MilaKit", package: "MilaKit"),
                .product(name: "TranscriptionCore", package: "TranscriptionCore"),
            ],
            path: "Port/Tests/ShimTests"
        ),
    ]
)
