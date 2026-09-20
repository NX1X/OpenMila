// swift-tools-version: 5.10
import PackageDescription

// Modified by NX1X for OpenMila; see CHANGES.md.
// Windows builds whisper.cpp from the pinned commit exactly as Linux does;
// the xcframework is macOS-only, so the system library is the default and
// the binary target is the macOS special case.
#if !os(macOS)
let whisperDep: Target = .systemLibrary(
    name: "whisper",
    path: "Sources/CWhisper"
)
#else
let whisperDep: Target = .binaryTarget(
    name: "whisper",
    url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.4/whisper-v1.8.4-xcframework.zip",
    checksum: "1c7a93bd20fe4e57e0af12051ddb34b7a434dfc9acc02c8313393150b6d1821f"
)
#endif

let package = Package(
    name: "TranscriptionCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TranscriptionCore", targets: ["TranscriptionCore"]),
        .executable(name: "whisper-e2e", targets: ["WhisperE2E"]),
    ],
    targets: [
        whisperDep,
        .target(
            name: "TranscriptionCore",
            dependencies: ["whisper"]
        ),
        .executableTarget(
            name: "WhisperE2E",
            dependencies: ["TranscriptionCore"]
        ),
        .testTarget(
            name: "TranscriptionCoreTests",
            dependencies: ["TranscriptionCore"]
        ),
    ]
)
