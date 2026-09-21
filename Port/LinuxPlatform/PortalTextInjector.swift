// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only.
#if os(Linux)

import CGio
import Foundation
import PlatformKit

/// Typing into the focused window on a Wayland session, through the
/// RemoteDesktop portal.
///
/// Dictation ends by putting text where the cursor is. On X11 that is XTest.
/// On Wayland no client may synthesise input for another, so the only route
/// is this portal, which asks the user once and then accepts keystrokes for
/// the life of the session. Without it the port can only leave the text on
/// the clipboard and say so, which works but is not what dictation means.
///
/// The user's consent is remembered: the portal hands back a restore token
/// the first time, which is kept beside the app's other state so later
/// sessions start without a dialog.
public final class PortalTextInjector {
    private let tokenStore: URL
    private var portal: PortalConnection?
    private var session: String?

    /// evdev key codes, which is what NotifyKeyboardKeycode takes. These are
    /// the kernel's numbers, not X11 keycodes and not keysyms.
    private enum Key: Int32 {
        case leftControl = 29
        case v = 47
    }

    public init(stateDirectory: URL) {
        tokenStore = stateDirectory.appendingPathComponent("remote-desktop-token")
    }

    public static var isAvailable: Bool {
        ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] != nil
            && PortalConnection.implements("org.freedesktop.portal.RemoteDesktop")
    }

    /// Whether the user has already allowed this, so a caller can offer the
    /// permission rather than discovering it mid-dictation.
    public var isGranted: Bool {
        FileManager.default.fileExists(atPath: tokenStore.path)
    }

    /// Asks for permission. This BLOCKS on a dialog the user has to answer,
    /// so it belongs to a button they pressed, never to a dictation: the
    /// first thing dictation does must not be to wait two minutes on a modal.
    @discardableResult
    public func requestPermission() -> Bool {
        ensureSession(allowDialog: true)
    }

    /// Presses Ctrl+V in the focused window. Returns false at once when
    /// permission has not been granted yet, so dictation falls back to the
    /// clipboard instead of stopping to ask.
    public func paste() -> Bool {
        guard session != nil || isGranted else { return false }
        guard ensureSession(allowDialog: false) else { return false }
        guard let portal, let session else { return false }

        // Down in order, up in reverse, which is what an actual keyboard does
        // and what applications expect to see.
        let sequence: [(Key, Int32)] = [
            (.leftControl, 1), (.v, 1), (.v, 0), (.leftControl, 0),
        ]
        for (key, state) in sequence {
            let arguments = variantTuple([
                g_variant_new_object_path(session),
                variantOptions([String: OpaquePointer]()),
                g_variant_new_int32(key.rawValue),
                g_variant_new_uint32(UInt32(state)),
            ])
            guard portal.call(interface: "org.freedesktop.portal.RemoteDesktop",
                              method: "NotifyKeyboardKeycode",
                              arguments: arguments) else { return false }
        }
        return true
    }

    // MARK: The session

    /// `allowDialog` is the difference between a button and a dictation: with
    /// a stored token the portal answers without asking anyone, which is fast
    /// enough to do inline; without one it shows a modal, which is not.
    private func ensureSession(allowDialog: Bool) -> Bool {
        if session != nil, portal != nil { return true }
        guard let portal = PortalConnection() else { return false }
        self.portal = portal

        let sessionToken = PortalConnection.token("openmila_rd")
        let createToken = PortalConnection.token()
        let created = portal.request(
            interface: "org.freedesktop.portal.RemoteDesktop",
            method: "CreateSession",
            token: createToken,
            arguments: variantTuple([variantOptions([
                "handle_token": createToken,
                "session_handle_token": sessionToken,
            ])]),
            timeout: 10)
        guard created.response == 0, let handle = variantString(in: created.results, key: "session_handle") else {
            if let results = created.results { g_variant_unref(results) }
            return false
        }
        if let results = created.results { g_variant_unref(results) }

        // 1 is KEYBOARD. The port asks for nothing else: it types, it does not
        // move the pointer or read the screen, and a portal request should be
        // exactly as wide as what it needs.
        let selectToken = PortalConnection.token()
        var selectOptions: [String: OpaquePointer] = [
            "handle_token": g_variant_new_string(selectToken)!,
            "types": g_variant_new_uint32(1)!,
            // 2 means "remember this until the user revokes it", which is what
            // keeps dictation from asking on every launch.
            "persist_mode": g_variant_new_uint32(2)!,
        ]
        if let restore = try? String(contentsOf: tokenStore, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !restore.isEmpty {
            selectOptions["restore_token"] = g_variant_new_string(restore)!
        }
        let selected = portal.request(
            interface: "org.freedesktop.portal.RemoteDesktop",
            method: "SelectDevices",
            token: selectToken,
            arguments: variantTuple([g_variant_new_object_path(handle), variantOptions(selectOptions)]),
            timeout: 10)
        if let results = selected.results { g_variant_unref(results) }
        guard selected.response == 0 else { return false }

        // Start is where the user sees the dialog, the first time only.
        let startToken = PortalConnection.token()
        let started = portal.request(
            interface: "org.freedesktop.portal.RemoteDesktop",
            method: "Start",
            token: startToken,
            arguments: variantTuple([
                g_variant_new_object_path(handle),
                g_variant_new_string(""),
                variantOptions(["handle_token": startToken]),
            ]),
            // With a stored token the portal answers by itself and this is
            // quick; without one a person has to read a dialog, and only a
            // caller that asked for that waits.
            timeout: allowDialog ? 120 : 5)
        defer { if let results = started.results { g_variant_unref(results) } }
        guard started.response == 0 else { return false }

        if let restore = variantString(in: started.results, key: "restore_token") {
            try? FileManager.default.createDirectory(at: tokenStore.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? restore.write(to: tokenStore, atomically: true, encoding: .utf8)
        }
        session = handle
        return true
    }
}
#endif
