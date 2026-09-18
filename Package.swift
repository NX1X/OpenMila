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
// (`Combine`, `OSLog`, `os`, `CryptoKit`). Off macOS no system module of that
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
        .library(name: "OpenMilaShims", targets: ["Combine", "OSLog", "os", "CryptoKit"]),
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
        .target(
            name: "CryptoKit",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")],
            path: "Port/Shims/CryptoKit"
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
