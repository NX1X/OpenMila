// swift-tools-version: 5.10
// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// The OpenMila desktop app. A separate package from the repository root so
// the root's `swift test` never builds the UI toolkit (whose Windows-only
// targets cannot compile on Linux under the current build tool), and so the
// app's heavy dependencies stay out of the core's dependency graph.
//
// Build from this directory:
//   swift build --build-system native -j 3 --product openmila <whisper flags>
import PackageDescription

let package = Package(
    name: "OpenMilaApp",
    dependencies: [
        .package(name: "OpenMila", path: "../.."),
        .package(url: "https://github.com/moreSwift/swift-cross-ui.git", exact: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "openmila",
            dependencies: [
                .product(name: "OpenMilaCore", package: "OpenMila"),
                .product(name: "OpenMilaLinux", package: "OpenMila", condition: .when(platforms: [.linux])),
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
                .product(name: "GtkBackend", package: "swift-cross-ui", condition: .when(platforms: [.linux])),
                .product(name: "Gtk", package: "swift-cross-ui", condition: .when(platforms: [.linux])),
            ],
            path: "Sources",
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
    ]
)
