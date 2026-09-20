// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// The POSIX calls upstream's portable sources make that Windows does not have.
//
// Like DarwinCompat, these live INSIDE the core module rather than in a shim
// module, so nothing else in the build can see the names.
//
// Two groups:
//   - things Windows can do differently (`kill`, `uname`), implemented here;
//   - the POSIX pseudo-terminal, which Windows genuinely lacks (it has ConPTY
//     instead). Those entry points exist so the file compiles and fail at run
//     time, which the caller already handles: `ClaudeSetupTokenSession` reports
//     "Couldn't open a terminal for the CLI". Browser sign-in for the managed
//     Claude install therefore needs a real terminal on Windows until a ConPTY
//     path is written; `docs/port/PARITY.md` records that.

#if os(Windows)
import Foundation
import WinSDK

// MARK: Signals

let SIGKILL: Int32 = 9
let SIGTERM: Int32 = 15

/// Ends a process the way `kill` does. Windows has no signals for another
/// process, so both SIGKILL and SIGTERM terminate it; callers use this only to
/// stop a child that has outstayed its timeout.
@discardableResult
func kill(_ pid: Int32, _ signal: Int32) -> Int32 {
    guard let handle = OpenProcess(DWORD(PROCESS_TERMINATE), false, DWORD(pid)) else { return -1 }
    defer { CloseHandle(handle) }
    return TerminateProcess(handle, UINT(signal)) ? 0 : -1
}

// MARK: uname

/// Enough of `struct utsname` for what upstream reads from it: the machine
/// name, in fixed-size storage so `withUnsafePointer(to:)` and
/// `MemoryLayout.size(ofValue:)` behave as they do on POSIX.
struct utsname {
    var machine: (Int64, Int64, Int64, Int64, Int64, Int64, Int64, Int64) = (0, 0, 0, 0, 0, 0, 0, 0)
    init() {}
}

/// `uname`, reduced to the architecture, which is all upstream asks for. The
/// names match POSIX's (`x86_64`, `arm64`) so the platform-key mapping needs no
/// Windows case.
func uname(_ info: UnsafeMutablePointer<utsname>) -> Int32 {
    var system = SYSTEM_INFO()
    GetNativeSystemInfo(&system)
    let machine: String
    switch Int32(system.wProcessorArchitecture) {
    case PROCESSOR_ARCHITECTURE_AMD64: machine = "x86_64"
    case PROCESSOR_ARCHITECTURE_ARM64: machine = "arm64"
    case PROCESSOR_ARCHITECTURE_INTEL: machine = "i686"
    default: return -1
    }
    let bytes = Array(machine.utf8)
    return withUnsafeMutablePointer(to: &info.pointee.machine) { storage in
        storage.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: info.pointee.machine)) { out in
            for (index, byte) in bytes.enumerated() { out[index] = CChar(byte) }
            out[bytes.count] = 0
            return 0
        }
    }
}

// MARK: Descriptor I/O

/// The POSIX `read` shape upstream uses: Windows' CRT takes an unsigned count
/// and returns `Int32`, so the Int-counted call does not type-check without
/// this.
func read(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
    Int(_read(descriptor, buffer, UInt32(clamping: count)))
}

// MARK: The POSIX pseudo-terminal Windows does not have

let O_NOCTTY: Int32 = 0

struct winsize {
    var ws_row: UInt16
    var ws_col: UInt16
    var ws_xpixel: UInt16
    var ws_ypixel: UInt16
}

func posix_openpt(_ flags: Int32) -> Int32 { -1 }
func grantpt(_ descriptor: Int32) -> Int32 { -1 }
func unlockpt(_ descriptor: Int32) -> Int32 { -1 }
func ptsname(_ descriptor: Int32) -> UnsafeMutablePointer<CChar>? { nil }

@discardableResult
func ioctl(_ descriptor: Int32, _ request: UInt, _ argument: UnsafeMutableRawPointer?) -> Int32 { -1 }
#endif
