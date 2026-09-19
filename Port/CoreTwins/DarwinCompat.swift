// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// The few Darwin-only C calls upstream's portable sources make.
//
// These live INSIDE the core module on purpose. A shim module named `Darwin`
// would make `canImport(Darwin)` true for every package in the build, and
// swift-log, OpenCombine and others use exactly that test to pick their
// platform code. Declaring the names here keeps them invisible to everyone
// else.

#if !canImport(Darwin)
import Foundation

/// Lets upstream's module-qualified `Darwin.write(...)` resolve.
enum Darwin {
    static func write(_ fd: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int {
        #if canImport(Glibc)
        return Glibc.write(fd, buffer, count)
        #elseif canImport(Musl)
        return Musl.write(fd, buffer, count)
        #else
        return -1
        #endif
    }
}

/// Darwin's sysctl-by-name. No such namespace elsewhere, so every lookup fails,
/// which callers read as "value unknown" (for example "not under Rosetta").
func sysctlbyname(
    _ name: UnsafePointer<CChar>,
    _ oldp: UnsafeMutableRawPointer?,
    _ oldlenp: UnsafeMutablePointer<Int>?,
    _ newp: UnsafeMutableRawPointer?,
    _ newlen: Int
) -> Int32 {
    -1
}

/// Darwin's three-argument `removexattr`. Upstream uses it only to clear the
/// macOS quarantine attribute, which does not exist elsewhere.
@discardableResult
func removexattr(_ path: UnsafePointer<CChar>, _ name: UnsafePointer<CChar>, _ options: Int32) -> Int32 {
    0
}
#endif
