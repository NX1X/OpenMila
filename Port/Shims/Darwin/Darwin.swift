// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// `import Darwin` (and module-qualified calls such as `Darwin.write`) off
// macOS. Re-exports the platform C library, and supplies the two Darwin-only
// calls upstream's portable sources make, with the result the caller already
// treats as "not applicable here".

@_exported import CDarwinCompat

#if canImport(Glibc)
@_exported import Glibc
#elseif canImport(Musl)
@_exported import Musl
#elseif canImport(ucrt)
@_exported import ucrt
#endif

/// Darwin's sysctl-by-name. There is no such namespace elsewhere, so every
/// lookup fails, which callers read as "value unknown" (for example "not
/// running under Rosetta").
public func sysctlbyname(
    _ name: UnsafePointer<CChar>,
    _ oldp: UnsafeMutableRawPointer?,
    _ oldlenp: UnsafeMutablePointer<Int>?,
    _ newp: UnsafeMutableRawPointer?,
    _ newlen: Int
) -> Int32 {
    -1
}

/// Darwin's three-argument `removexattr(path, name, options)`. Upstream uses it
/// only to clear the macOS quarantine attribute, which does not exist on other
/// systems, so there is nothing to remove.
@discardableResult
public func removexattr(
    _ path: UnsafePointer<CChar>,
    _ name: UnsafePointer<CChar>,
    _ options: Int32
) -> Int32 {
    0
}
