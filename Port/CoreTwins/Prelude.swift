// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Module-wide imports for the `Mila` core when built off macOS.
//
// On Apple platforms `import Foundation` also brings in Combine and
// URLSession. Elsewhere Combine is the OpenCombine shim and URLSession lives
// in FoundationNetworking. An `@_exported import` in any one file of a module
// is visible to every file in it, so this single file covers upstream sources
// that rely on the Apple behaviour, without editing them.

@_exported import Combine

#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif

// Upstream calls POSIX functions (pty setup, `uname`) that Foundation re-exports
// on Apple platforms. Elsewhere they come from the C library via this shim.
@_exported import Darwin
