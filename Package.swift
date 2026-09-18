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
// (`Combine`, `OSLog`, `os`, `CryptoKit`, `Accelerate`, `SwiftUI`, `Darwin`). Off macOS no system module of that
// name exists, so upstream's `import Combine` lines compile unchanged against
// the open-source replacement. They must never be declared on macOS, where
// they would shadow the real frameworks.
import PackageDescription

#if os(macOS)
#error("Build OpenMila's macOS variant from upstream's project.yml; this manifest targets Linux and Windows.")
#endif

let package = Package(
    name: "OpenMila",
    products: [
        .library(name: "OpenMilaShims", targets: ["Combine", "OSLog", "os", "CryptoKit", "Accelerate"]),
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
        .target(name: "CDarwinCompat", path: "Port/Shims/CDarwinCompat"),
        .target(name: "Darwin", dependencies: ["CDarwinCompat"], path: "Port/Shims/Darwin"),
        .target(
            name: "CryptoKit",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")],
            path: "Port/Shims/CryptoKit"
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
                "Combine", "OSLog", "os", "CryptoKit", "Accelerate", "SwiftUI", "Darwin",
                .product(name: "MilaKit", package: "MilaKit"),
                .product(name: "TranscriptionCore", package: "TranscriptionCore"),
            ],
            // Rooted at the repository so the target can take upstream's tree
            // and the port twins together; `sources` keeps it to those two.
            path: ".",
            exclude: [
                // Everything at the root that is not this target's business.
                "Packages", "MilaTests", "MilaUITests", "MilaMCP", "Port/Shims", "Port/Tests",
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
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        ),

        // MARK: Tests
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
