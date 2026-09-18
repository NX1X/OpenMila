// swift-tools-version: 5.10
// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Phase 0 spike: can SwiftCrossUI carry OpenMila's UI? Kept as its own package
// so the experiment's dependency graph stays out of the main manifest until
// the answer is yes.
import PackageDescription

let package = Package(
    name: "UISpike",
    dependencies: [
        .package(url: "https://github.com/moreSwift/swift-cross-ui.git", exact: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "UISpike",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
            ]
        ),
    ]
)
