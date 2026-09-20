// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

#if os(Windows)
import CWinShim
import Foundation
import PlatformKit
import WinSDK

/// Global hotkeys through `RegisterHotKey`. Upstream: `HotkeyManager`
/// (Carbon `RegisterEventHotKey`).
///
/// Windows delivers `WM_HOTKEY` to a thread's message queue, so registration
/// and the message loop live on one dedicated thread; callers hand work back
/// to the main actor.
public final class WindowsHotkeys: GlobalHotkeys, @unchecked Sendable {
    private struct Registration {
        let id: Int32
        let chord: HotkeyChord
        let handler: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var registrations: [String: Registration] = [:]
    private var suspended: [String: Registration] = [:]
    private var nextID: Int32 = 1
    private var threadID: DWORD = 0
    private var ready = DispatchSemaphore(value: 0)

    /// Requests handed to the message thread, which owns every registration.
    private enum Request {
        case register(id: Int32, modifiers: UINT, key: UINT, reply: (Bool) -> Void)
        case unregister(id: Int32)
        case probe(modifiers: UINT, key: UINT, reply: (Bool) -> Void)
    }
    private var queue: [Request] = []

    private static let wmRequest = UINT(WM_APP + 2)

    public init() {
        let thread = Thread { [weak self] in self?.pump() }
        thread.name = "io.github.nx1x.openmila.hotkeys"
        thread.stackSize = 512 * 1024
        thread.start()
        ready.wait()
    }

    // MARK: GlobalHotkeys

    public func register(id: String, chord: HotkeyChord,
                         onPressed: @escaping @Sendable () -> Void) async -> HotkeyRegistrationResult {
        guard let key = Self.virtualKey(for: chord.key) else { return .unavailable }
        await unregister(id: id)
        let hotkeyID: Int32 = lock.withLock { let value = nextID; nextID += 1; return value }
        let ok = await withCheckedContinuation { continuation in
            post(.register(id: hotkeyID, modifiers: Self.modifiers(chord.modifiers), key: key) {
                continuation.resume(returning: $0)
            })
        }
        guard ok else { return .unavailable }
        lock.withLock { registrations[id] = Registration(id: hotkeyID, chord: chord, handler: onPressed) }
        return .registered
    }

    public func unregister(id: String) async {
        guard let registration = lock.withLock({ registrations.removeValue(forKey: id) }) else { return }
        post(.unregister(id: registration.id))
    }

    public func canRegister(_ chord: HotkeyChord) async -> Bool {
        guard let key = Self.virtualKey(for: chord.key) else { return false }
        return await withCheckedContinuation { continuation in
            post(.probe(modifiers: Self.modifiers(chord.modifiers), key: key) { continuation.resume(returning: $0) })
        }
    }

    public func suspendAll() async {
        let current = lock.withLock { () -> [String: Registration] in
            guard suspended.isEmpty else { return [:] }
            suspended = registrations
            registrations = [:]
            return suspended
        }
        for registration in current.values { post(.unregister(id: registration.id)) }
    }

    public func resumeAll() async {
        let parked = lock.withLock { () -> [String: Registration] in
            let value = suspended
            suspended = [:]
            return value
        }
        for (id, registration) in parked {
            _ = await register(id: id, chord: registration.chord, onPressed: registration.handler)
        }
    }

    // MARK: Message thread

    private func post(_ request: Request) {
        lock.withLock { queue.append(request) }
        PostThreadMessageW(threadID, Self.wmRequest, 0, 0)
    }

    private func pump() {
        threadID = GetCurrentThreadId()
        var message = MSG()
        // Force the queue to exist before anyone posts to it.
        PeekMessageW(&message, nil, UINT(WM_USER), UINT(WM_USER), UINT(PM_NOREMOVE))
        ready.signal()

        while GetMessageW(&message, nil, 0, 0) > 0 {
            switch message.message {
            case UINT(WM_HOTKEY):
                let hotkeyID = Int32(message.wParam)
                let handler = lock.withLock { registrations.values.first { $0.id == hotkeyID }?.handler }
                handler?()
            case Self.wmRequest:
                let pending = lock.withLock { () -> [Request] in
                    let value = queue
                    queue = []
                    return value
                }
                for request in pending { handle(request) }
            default:
                TranslateMessage(&message)
                DispatchMessageW(&message)
            }
        }
    }

    private func handle(_ request: Request) {
        switch request {
        case .register(let id, let modifiers, let key, let reply):
            reply(RegisterHotKey(nil, id, modifiers | UINT(MOD_NOREPEAT), key))
        case .unregister(let id):
            UnregisterHotKey(nil, id)
        case .probe(let modifiers, let key, let reply):
            let probeID: Int32 = 0x4F4D  // "OM"
            let ok = RegisterHotKey(nil, probeID, modifiers | UINT(MOD_NOREPEAT), key)
            if ok { UnregisterHotKey(nil, probeID) }
            reply(ok)
        }
    }

    // MARK: Chord translation

    static func modifiers(_ modifiers: HotkeyChord.Modifiers) -> UINT {
        var mask: UINT = 0
        if modifiers.contains(.control) { mask |= UINT(MOD_CONTROL) }
        if modifiers.contains(.alt) { mask |= UINT(MOD_ALT) }
        if modifiers.contains(.shift) { mask |= UINT(MOD_SHIFT) }
        if modifiers.contains(.meta) { mask |= UINT(MOD_WIN) }
        return mask
    }

    /// Layout-independent key names to Windows virtual-key codes.
    static func virtualKey(for key: String) -> UINT? {
        switch key.uppercased() {
        case "SPACE": return UINT(VK_SPACE)
        case "RETURN", "ENTER": return UINT(VK_RETURN)
        case "ESCAPE", "ESC": return UINT(VK_ESCAPE)
        case "TAB": return UINT(VK_TAB)
        default: break
        }
        let name = key.uppercased()
        if name.count == 1, let scalar = name.unicodeScalars.first {
            if scalar.value >= 0x30 && scalar.value <= 0x39 { return UINT(scalar.value) }  // 0-9
            if scalar.value >= 0x41 && scalar.value <= 0x5A { return UINT(scalar.value) }  // A-Z
        }
        if name.hasPrefix("F"), let number = Int(name.dropFirst()), (1...24).contains(number) {
            return UINT(Int32(VK_F1) + Int32(number - 1))
        }
        return nil
    }

    deinit {
        for registration in registrations.values { post(.unregister(id: registration.id)) }
        PostThreadMessageW(threadID, UINT(WM_QUIT), 0, 0)
    }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
#endif
