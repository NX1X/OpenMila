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

// The UI toolkit's own manifest says why this is a host `#if` and not a
// platform condition: "With no #if here, Windows and Linux dependencies are
// also compiled when building for UIKit platforms." A conditional product
// dependency still puts the target in the graph, so a Windows build tried to
// compile CGtk and stopped at "'gtk/gtk.h' file not found". The port builds
// natively on each system, so the host is the target.
#if os(Windows)
let backendDependencies: [Target.Dependency] = [
    .product(name: "OpenMilaWindows", package: "OpenMila"),
    .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
    .product(name: "DefaultBackend", package: "swift-cross-ui"),
]
#else
let backendDependencies: [Target.Dependency] = [
    .product(name: "OpenMilaLinux", package: "OpenMila"),
    .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
    .product(name: "DefaultBackend", package: "swift-cross-ui"),
    .product(name: "GtkBackend", package: "swift-cross-ui"),
    .product(name: "Gtk", package: "swift-cross-ui"),
]
#endif

let package = Package(
    name: "OpenMilaApp",
    dependencies: [
        .package(name: "OpenMila", path: "../.."),
        .package(url: "https://github.com/moreSwift/swift-cross-ui.git", exact: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "openmila",
            dependencies: [.product(name: "OpenMilaCore", package: "OpenMila")] + backendDependencies,
            path: "Sources",
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
    ]
)
