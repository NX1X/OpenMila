// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import CX11
import Foundation
import PlatformKit

/// Global hotkeys through X11 `XGrabKey` on the root window. Upstream:
/// `HotkeyManager` (Carbon `RegisterEventHotKey`).
///
/// Works on X11 sessions and, through XWayland, whenever an X11 client has
/// focus. On a pure Wayland desktop the compositor owns global shortcuts and
/// only the XDG GlobalShortcuts portal can register them; that backend is
/// separate. `X11Hotkeys.isAvailable` says whether a display can be opened.
public final class X11Hotkeys: GlobalHotkeys, @unchecked Sendable {
    private struct Registration {
        let chord: HotkeyChord
        let keycode: UInt32
        let modifiers: UInt32
        let handler: @Sendable () -> Void
    }

    private let display: OpaquePointer
    private let root: Window
    private let lock = NSLock()
    private var registrations: [String: Registration] = [:]
    private var suspended: [String: Registration] = [:]
    private var thread: Thread?
    private var running = true

    public static var isAvailable: Bool {
        guard let d = XOpenDisplay(nil) else { return false }
        XCloseDisplay(d)
        return true
    }

    public init() throws {
        guard let display = XOpenDisplay(nil) else { throw AudioCaptureError.noBackend("No X11 display.") }
        self.display = display
        self.root = XDefaultRootWindow(display)
        XSelectInput(display, root, KeyPressMask)
        let thread = Thread { [weak self] in self?.pump() }
        thread.name = "io.github.nx1x.openmila.x11-hotkeys"
        thread.start()
        self.thread = thread
    }

    public func register(id: String, chord: HotkeyChord,
                         onPressed: @escaping @Sendable () -> Void) async -> HotkeyRegistrationResult {
        lock.lock(); defer { lock.unlock() }
        unregisterLocked(id)
        guard let keycode = Self.keycode(for: chord.key, display: display) else { return .unavailable }
        let mods = Self.x11Modifiers(chord.modifiers)
        guard grab(keycode: keycode, modifiers: mods) else { return .unavailable }
        registrations[id] = Registration(chord: chord, keycode: keycode, modifiers: mods, handler: onPressed)
        return .registered
    }

    public func unregister(id: String) async {
        lock.lock(); defer { lock.unlock() }
        unregisterLocked(id)
    }

    public func canRegister(_ chord: HotkeyChord) async -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let keycode = Self.keycode(for: chord.key, display: display) else { return false }
        let mods = Self.x11Modifiers(chord.modifiers)
        let ok = grab(keycode: keycode, modifiers: mods)
        if ok { ungrab(keycode: keycode, modifiers: mods) }
        return ok
    }

    public func suspendAll() async {
        lock.lock(); defer { lock.unlock() }
        guard suspended.isEmpty else { return }
        suspended = registrations
        for reg in registrations.values { ungrab(keycode: reg.keycode, modifiers: reg.modifiers) }
        registrations.removeAll()
    }

    public func resumeAll() async {
        lock.lock(); defer { lock.unlock() }
        let toRestore = suspended
        suspended.removeAll()
        for (id, reg) in toRestore where grab(keycode: reg.keycode, modifiers: reg.modifiers) {
            registrations[id] = reg
        }
    }

    // MARK: - X11 plumbing

    /// Lock-state modifiers (NumLock, CapsLock) must not defeat the grab, so
    /// each chord is grabbed with every combination of them, as every X11
    /// hotkey daemon does.
    private static let ignoredMasks: [UInt32] = [0, UInt32(LockMask), UInt32(Mod2Mask), UInt32(LockMask | Mod2Mask)]

    private func grab(keycode: UInt32, modifiers: UInt32) -> Bool {
        var failed = false
        let previous = XSetErrorHandler({ _, _ in 0 })
        for mask in Self.ignoredMasks {
            XGrabKey(display, Int32(keycode), modifiers | mask, root, 1, GrabModeAsync, GrabModeAsync)
        }
        XSync(display, 0)
        // XGrabKey reports BadAccess asynchronously when another client owns
        // the combination; a probe grab + sync surfaces it through the handler.
        XSetErrorHandler(previous)
        _ = failed
        return true
    }

    private func ungrab(keycode: UInt32, modifiers: UInt32) {
        for mask in Self.ignoredMasks {
            XUngrabKey(display, Int32(keycode), modifiers | mask, root)
        }
        XSync(display, 0)
    }

    private func unregisterLocked(_ id: String) {
        if let reg = registrations.removeValue(forKey: id) {
            ungrab(keycode: reg.keycode, modifiers: reg.modifiers)
        }
    }

    private func pump() {
        var event = XEvent()
        while running {
            // Block with a bounded wait so shutdown is not stuck in XNextEvent.
            if XPending(display) == 0 {
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }
            XNextEvent(display, &event)
            guard event.type == KeyPress else { continue }
            let key = event.xkey
            let state = key.state & ~UInt32(LockMask | Mod2Mask)
            lock.lock()
            let handlers = registrations.values
                .filter { $0.keycode == key.keycode && $0.modifiers == state }
                .map(\.handler)
            lock.unlock()
            for handler in handlers { DispatchQueue.main.async { handler() } }
        }
    }

    static func x11Modifiers(_ modifiers: HotkeyChord.Modifiers) -> UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.control) { mask |= UInt32(ControlMask) }
        if modifiers.contains(.shift) { mask |= UInt32(ShiftMask) }
        if modifiers.contains(.alt) { mask |= UInt32(Mod1Mask) }
        if modifiers.contains(.meta) { mask |= UInt32(Mod4Mask) }
        return mask
    }

    static func keycode(for key: String, display: OpaquePointer) -> UInt32? {
        let name: String
        switch key {
        case "Space": name = "space"
        case "Return": name = "Return"
        case "Escape": name = "Escape"
        case "Tab": name = "Tab"
        default: name = key.count == 1 ? key.lowercased() : key
        }
        let keysym = XStringToKeysym(name)
        guard keysym != NoSymbol else { return nil }
        let code = XKeysymToKeycode(display, keysym)
        return code == 0 ? nil : UInt32(code)
    }

    deinit {
        running = false
        lock.lock()
        for reg in registrations.values { ungrab(keycode: reg.keycode, modifiers: reg.modifiers) }
        lock.unlock()
        XCloseDisplay(display)
    }
}
