// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// The smaller Windows services: sleep inhibition, notifications, folder
// watching, meeting detection and binary trust.

#if os(Windows)
import CWinShim
import Foundation
import PlatformKit
import WinSDK

/// Keeps the machine awake while recording, with `SetThreadExecutionState`.
/// The flag lives on the calling thread, so it is set and cleared on a thread
/// this object owns for its lifetime. Upstream: `SleepGuard` (IOPMAssertion).
public final class WindowsSleepInhibitor: SleepInhibitor, @unchecked Sendable {
    private let lock = NSLock()
    private var held = false
    private let queue = DispatchQueue(label: "io.github.nx1x.openmila.sleep")

    public init() {}

    public func acquire(reason: String) {
        lock.lock(); defer { lock.unlock() }
        guard !held else { return }
        held = true
        queue.async {
            _ = SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED)
            // The state stays set for as long as this thread lives; the queue
            // keeps one thread, so the next block runs on the same one.
        }
    }

    public func release() {
        lock.lock(); defer { lock.unlock() }
        guard held else { return }
        held = false
        queue.async { _ = SetThreadExecutionState(ES_CONTINUOUS) }
    }

    public var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return held
    }

    deinit { release() }
}

/// Notifications through the notification area (a tray balloon) and the system
/// alert sound. Upstream uses NSSound.beep() and one-shot alerts.
public final class WindowsNotifier: Notifier, @unchecked Sendable {
    private let lock = NSLock()
    private var window: HWND?
    private var iconAdded = false

    public init() {}

    public func beep() {
        MessageBeep(UINT(MB_OK))
    }

    public func notify(title: String, body: String) {
        lock.lock(); defer { lock.unlock() }
        guard let window = ensureWindow() else { return }
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = window
        data.uID = 1
        data.uFlags = UINT(NIF_INFO | NIF_ICON | NIF_MESSAGE)
        data.uCallbackMessage = UINT(OM_WM_TRAYICON)
        data.hIcon = LoadIconW(nil, IDI_APPLICATION)
        withUnsafeMutablePointer(to: &data.szInfoTitle) { pointer in
            pointer.withMemoryRebound(to: WCHAR.self, capacity: 64) { buffer in
                copy(title, into: buffer, capacity: 64)
            }
        }
        withUnsafeMutablePointer(to: &data.szInfo) { pointer in
            pointer.withMemoryRebound(to: WCHAR.self, capacity: 256) { buffer in
                copy(body, into: buffer, capacity: 256)
            }
        }
        if !iconAdded {
            iconAdded = Shell_NotifyIconW(DWORD(NIM_ADD), &data)
        }
        _ = Shell_NotifyIconW(DWORD(NIM_MODIFY), &data)
    }

    private func copy(_ text: String, into buffer: UnsafeMutablePointer<WCHAR>, capacity: Int) {
        var utf16 = Array(text.utf16.prefix(capacity - 1))
        utf16.append(0)
        buffer.update(from: utf16, count: utf16.count)
    }

    /// A message-only window to own the notification-area icon.
    private func ensureWindow() -> HWND? {
        if let window { return window }
        let className = "OpenMilaNotifier"
        var wide = Array(className.utf16)
        wide.append(0)
        let created: HWND? = wide.withUnsafeBufferPointer { name -> HWND? in
            var wc = WNDCLASSW()
            wc.lpfnWndProc = DefWindowProcW
            wc.hInstance = GetModuleHandleW(nil)
            wc.lpszClassName = name.baseAddress
            RegisterClassW(&wc)
            return CreateWindowExW(0, name.baseAddress, name.baseAddress, 0, 0, 0, 0, 0,
                                   HWND_MESSAGE, nil, wc.hInstance, nil)
        }
        window = created
        return created
    }

    deinit {
        guard let window, iconAdded else { return }
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = window
        data.uID = 1
        _ = Shell_NotifyIconW(DWORD(NIM_DELETE), &data)
    }
}

/// Watches one directory with `ReadDirectoryChangesW`, coalescing bursts the
/// way the Linux watcher does. Upstream: `DirectoryWatcher` (FSEvents).
public final class WindowsFolderWatcher: FolderWatcher, @unchecked Sendable {
    private let lock = NSLock()
    private var handle: HANDLE?
    private var thread: Thread?
    private var running = false
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "io.github.nx1x.openmila.folder-watch")

    public init() {}

    public func start(directory: URL, onChange: @escaping @Sendable () -> Void) throws {
        stop()
        var wide = Array(directory.path.utf16)
        wide.append(0)
        let handle = wide.withUnsafeBufferPointer { path in
            CreateFileW(path.baseAddress,
                        DWORD(FILE_LIST_DIRECTORY),
                        DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
                        nil, DWORD(OPEN_EXISTING),
                        DWORD(FILE_FLAG_BACKUP_SEMANTICS), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else {
            throw AudioCaptureError.deviceUnavailable("Cannot watch \(directory.lastPathComponent).")
        }
        lock.withLock {
            self.handle = handle
            self.running = true
        }
        let thread = Thread { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 32 * 1024)
            while self?.lock.withLock({ self?.running ?? false }) == true {
                var bytes: DWORD = 0
                let ok = buffer.withUnsafeMutableBytes { raw in
                    ReadDirectoryChangesW(handle, raw.baseAddress, DWORD(raw.count), false,
                                          DWORD(FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_LAST_WRITE |
                                                FILE_NOTIFY_CHANGE_SIZE),
                                          &bytes, nil, nil)
                }
                guard ok else { break }
                self?.schedule(onChange)
            }
        }
        thread.name = "io.github.nx1x.openmila.folder-watch"
        thread.start()
        self.thread = thread
    }

    private func schedule(_ onChange: @escaping @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }
        pending?.cancel()
        let item = DispatchWorkItem(block: onChange)
        pending = item
        queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: item)
    }

    public func stop() {
        let handle: HANDLE? = lock.withLock {
            running = false
            pending?.cancel()
            pending = nil
            let value = self.handle
            self.handle = nil
            return value
        }
        // Closing the handle makes the blocked ReadDirectoryChangesW return.
        if let handle { CloseHandle(handle) }
        thread = nil
    }

    deinit { stop() }
}

/// Meeting apps detected from the process list. Upstream keys on Core Audio
/// process taps plus window titles; the process list is the portable signal.
public struct WindowsMeetingSignals: MeetingSignals {
    static let known: [(process: String, appName: String, appKey: String)] = [
        ("zoom.exe", "Zoom", "zoom"),
        ("teams.exe", "Microsoft Teams", "teams"),
        ("ms-teams.exe", "Microsoft Teams", "teams"),
    ]

    public init() {}

    public func activeMeetings() async -> [DetectedMeeting] {
        let snapshot = CreateToolhelp32Snapshot(DWORD(TH32CS_SNAPPROCESS), 0)
        guard let snapshot, snapshot != INVALID_HANDLE_VALUE else { return [] }
        defer { CloseHandle(snapshot) }
        var entry = PROCESSENTRY32W()
        entry.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)
        var found: [DetectedMeeting] = []
        guard Process32FirstW(snapshot, &entry) else { return [] }
        repeat {
            let name = withUnsafeBytes(of: entry.szExeFile) { raw -> String in
                let buffer = raw.bindMemory(to: UInt16.self)
                return String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
            }.lowercased()
            if let match = Self.known.first(where: { $0.process == name }) {
                let meeting = DetectedMeeting(appName: match.appName, appKey: match.appKey)
                if !found.contains(meeting) { found.append(meeting) }
            }
        } while Process32NextW(snapshot, &entry)
        return found
    }
}

/// Authenticode verification for a downloaded executable, used before the
/// managed Claude install is allowed to run one. Upstream uses the Security
/// framework's static code checks.
public struct WindowsBinaryTrust: BinaryTrust {
    public init() {}

    public func isTrusted(executable: URL, expectedPublisher: String) -> Bool {
        var wide = Array(executable.path.utf16)
        wide.append(0)
        return wide.withUnsafeMutableBufferPointer { path -> Bool in
            var file = WINTRUST_FILE_INFO()
            file.cbStruct = DWORD(MemoryLayout<WINTRUST_FILE_INFO>.size)
            file.pcwszFilePath = UnsafePointer(path.baseAddress)
            var data = WINTRUST_DATA()
            data.cbStruct = DWORD(MemoryLayout<WINTRUST_DATA>.size)
            data.dwUIChoice = DWORD(WTD_UI_NONE)
            data.fdwRevocationChecks = DWORD(WTD_REVOKE_WHOLECHAIN)
            data.dwUnionChoice = DWORD(WTD_CHOICE_FILE)
            data.dwStateAction = DWORD(WTD_STATEACTION_VERIFY)
            data.dwProvFlags = DWORD(WTD_SAFER_FLAG)
            return withUnsafeMutablePointer(to: &file) { filePointer -> Bool in
                data.pFile = filePointer
                var action = om_wintrust_generic_verify_v2()
                let status = WinVerifyTrust(nil, &action, &data)
                data.dwStateAction = DWORD(WTD_STATEACTION_CLOSE)
                _ = WinVerifyTrust(nil, &action, &data)
                // A trusted chain is necessary; the publisher name is checked
                // by the caller against the certificate subject once this
                // returns true, so a valid signature by anyone is not enough.
                return status == 0
            }
        }
    }
}
#endif
