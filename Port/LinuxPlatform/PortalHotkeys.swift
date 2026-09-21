// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only.
#if os(Linux)

import CGio
import Foundation
import PlatformKit

/// Global shortcuts on Wayland, through the XDG GlobalShortcuts portal.
///
/// X11 lets any client grab a key combination for itself, which is what
/// `X11Hotkeys` does. Wayland deliberately does not: the compositor owns
/// input, and an application that wants a shortcut has to ask the portal,
/// which asks the user once and then tells the application when the shortcut
/// fires. That is the only route, so dictation hotkeys on a Wayland session
/// live or die by this file.
///
/// The portal is asynchronous in a way that matters: every call returns a
/// Request object path, and the answer arrives later as a Response signal on
/// that path. A session must be created first, shortcuts bound to it second
/// (which is when the user sees a dialog), and Activated signals watched for
/// the rest of the session. All of that needs a GMainContext running
/// somewhere, so this object owns a thread for one.
public final class PortalHotkeys: GlobalHotkeys, @unchecked Sendable {
    private struct Binding {
        let chord: HotkeyChord
        let handler: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var bindings: [String: Binding] = [:]
    private var suspended: [String: Binding] = [:]
    private var sessionHandle: String?
    private var connection: OpaquePointer?      // GDBusConnection
    private var context: OpaquePointer?         // GMainContext
    private var loop: OpaquePointer?            // GMainLoop
    private var activatedSubscription: UInt32 = 0
    private let ready = DispatchSemaphore(value: 0)
    private var started = false

    public init?() {
        guard Self.isAvailable else { return nil }
        let thread = Thread { [self] in run() }
        thread.name = "io.github.nx1x.openmila.portal-hotkeys"
        thread.stackSize = 512 * 1024
        thread.start()
        // The session must exist before anything can be bound to it. Giving up
        // rather than hanging keeps a broken portal from blocking startup.
        if ready.wait(timeout: .now() + 10) == .timedOut { return nil }
        guard lock.withLock({ sessionHandle != nil }) else { return nil }
    }

    /// True when a desktop portal answers and offers GlobalShortcuts. GNOME 48
    /// and KDE do; an X11-only session usually does not, and there the caller
    /// uses `X11Hotkeys` instead.
    public static var isAvailable: Bool {
        guard ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] != nil else { return false }
        var error: UnsafeMutablePointer<GError>?
        guard let connection = g_bus_get_sync(G_BUS_TYPE_SESSION, nil, &error) else {
            if let error { g_error_free(error) }
            return false
        }
        defer { g_object_unref(UnsafeMutableRawPointer(connection)) }
        // Asking for the interface's version is the cheapest way to learn
        // whether the portal implements it at all.
        let reply = g_dbus_connection_call_sync(
            connection,
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.DBus.Properties",
            "Get",
            Self.tuple([
                g_variant_new_string("org.freedesktop.portal.GlobalShortcuts"),
                g_variant_new_string("version"),
            ]),
            nil, GDBusCallFlags(rawValue: 0), 2000, nil, &error)
        if let error {
            g_error_free(error)
            return false
        }
        if let reply { g_variant_unref(reply) }
        return true
    }

    // MARK: The portal conversation

    private func run() {
        context = g_main_context_new()
        g_main_context_push_thread_default(context)
        defer {
            g_main_context_pop_thread_default(context)
            if let context { g_main_context_unref(context) }
        }

        var error: UnsafeMutablePointer<GError>?
        guard let connection = g_bus_get_sync(G_BUS_TYPE_SESSION, nil, &error) else {
            if let error {
                Self.report("no session bus: \(String(cString: error.pointee.message))")
                g_error_free(error)
            }
            ready.signal()
            return
        }
        self.connection = connection

        guard let session = createSession(on: connection) else {
            ready.signal()
            return
        }
        lock.withLock { sessionHandle = session }
        subscribeToActivations(on: connection)
        ready.signal()

        loop = g_main_loop_new(context, 0)
        g_main_loop_run(loop)
    }

    /// CreateSession, then wait for its Response signal. The portal answers on
    /// a Request object path derived from the token it was given.
    private func createSession(on connection: OpaquePointer) -> String? {
        let requestToken = "openmila_\(UInt32.random(in: 1...UInt32.max))"
        let sessionToken = "openmila_\(UInt32.random(in: 1...UInt32.max))"

        var result: String?
        let waiter = DispatchSemaphore(value: 0)
        let requestPath = Self.requestPath(on: connection, token: requestToken)

        let box = ResponseBox { response, results in
            defer { waiter.signal() }
            guard response == 0 else {
                Self.report("the portal refused the session (response \(response))")
                return
            }
            result = Self.string(in: results, key: "session_handle")
        }
        let subscription = subscribeResponse(on: connection, path: requestPath, box: box)

        var error: UnsafeMutablePointer<GError>?
        let options = Self.tuple([Self.options([
            "handle_token": requestToken,
            "session_handle_token": sessionToken,
        ])])
        let reply = g_dbus_connection_call_sync(
            connection,
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.GlobalShortcuts",
            "CreateSession",
            options,
            nil, GDBusCallFlags(rawValue: 0), 5000, nil, &error)
        if let error {
            Self.report("CreateSession failed: \(String(cString: error.pointee.message))")
            g_error_free(error)
            g_dbus_connection_signal_unsubscribe(connection, subscription)
            return nil
        }
        if let reply { g_variant_unref(reply) }

        // Pump this thread's context until the Response signal lands.
        let deadline = Date().addingTimeInterval(10)
        while waiter.wait(timeout: .now() + .milliseconds(20)) == .timedOut, Date() < deadline {
            while g_main_context_iteration(context, 0) != 0 {}
        }
        g_dbus_connection_signal_unsubscribe(connection, subscription)
        return result
    }

    // MARK: GlobalHotkeys

    public func register(id: String, chord: HotkeyChord,
                         onPressed: @escaping @Sendable () -> Void) async -> HotkeyRegistrationResult {
        guard lock.withLock({ sessionHandle != nil }) else { return .unavailable }
        lock.withLock { bindings[id] = Binding(chord: chord, handler: onPressed) }
        return bindAll() ? .registered : .unavailable
    }

    public func unregister(id: String) async {
        lock.withLock { _ = bindings.removeValue(forKey: id) }
        _ = bindAll()
    }

    /// The portal has no probe: a combination is a preference, and the
    /// compositor decides what it can actually deliver. Anything the port can
    /// express is worth offering, so this answers yes and the user finds out
    /// in the portal's own dialog.
    public func canRegister(_ chord: HotkeyChord) async -> Bool {
        Self.trigger(for: chord) != nil
    }

    public func suspendAll() async {
        lock.withLock {
            guard suspended.isEmpty else { return }
            suspended = bindings
            bindings = [:]
        }
        _ = bindAll()
    }

    public func resumeAll() async {
        lock.withLock {
            guard !suspended.isEmpty else { return }
            bindings = suspended
            suspended = [:]
        }
        _ = bindAll()
    }

    /// BindShortcuts replaces the whole set, so every change rebinds all of
    /// them. The user sees the portal's dialog the first time; afterwards the
    /// desktop remembers the choice for this application.
    private func bindAll() -> Bool {
        guard let connection, let session = lock.withLock({ sessionHandle }) else { return false }
        let current = lock.withLock { bindings }

        let builder = g_variant_builder_new(g_variant_type_new("a(sa{sv})"))
        defer { g_variant_builder_unref(builder) }
        for (id, binding) in current {
            guard let trigger = Self.trigger(for: binding.chord) else { continue }
            g_variant_builder_add_value(builder, Self.tuple([
                g_variant_new_string(id),
                Self.options([
                    "description": "OpenMila: \(id)",
                    "preferred_trigger": trigger,
                ]),
            ]))
        }

        var error: UnsafeMutablePointer<GError>?
        let arguments = Self.tuple([
            g_variant_new_object_path(session),
            g_variant_builder_end(builder),
            g_variant_new_string(""),
            Self.options([:]),
        ])
        let reply = g_dbus_connection_call_sync(
            connection,
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.GlobalShortcuts",
            "BindShortcuts",
            arguments,
            nil, GDBusCallFlags(rawValue: 0), 30000, nil, &error)
        if let error {
            Self.report("BindShortcuts failed: \(String(cString: error.pointee.message))")
            g_error_free(error)
            return false
        }
        if let reply { g_variant_unref(reply) }
        return true
    }

    /// The Activated signal carries the shortcut id that fired.
    private func subscribeToActivations(on connection: OpaquePointer) {
        let box = ActivatedBox { [weak self] id in
            guard let self else { return }
            let handler = self.lock.withLock { self.bindings[id]?.handler }
            handler?()
        }
        activatedSubscription = g_dbus_connection_signal_subscribe(
            connection,
            "org.freedesktop.portal.Desktop",
            "org.freedesktop.portal.GlobalShortcuts",
            "Activated",
            "/org/freedesktop/portal/desktop",
            nil,
            GDBusSignalFlags(rawValue: 0),
            { _, _, _, _, _, parameters, user in
                guard let user, let parameters else { return }
                let box = Unmanaged<ActivatedBox>.fromOpaque(user).takeUnretainedValue()
                // (o s t a{sv}): session, shortcut id, timestamp, options.
                guard let child = g_variant_get_child_value(parameters, 1) else { return }
                defer { g_variant_unref(child) }
                if let raw = g_variant_get_string(child, nil) {
                    box.fire(String(cString: raw))
                }
            },
            Unmanaged.passRetained(box).toOpaque(),
            { user in
                guard let user else { return }
                Unmanaged<ActivatedBox>.fromOpaque(user).release()
            })
    }

    // MARK: Translation and plumbing

    /// The portal's trigger syntax: modifiers and a key name joined by "+",
    /// as in "CTRL+ALT+2". It is a PREFERENCE, not a demand: the compositor
    /// may hand the user a different combination, and the Activated signal is
    /// what matters afterwards.
    static func trigger(for chord: HotkeyChord) -> String? {
        var parts: [String] = []
        if chord.modifiers.contains(.control) { parts.append("CTRL") }
        if chord.modifiers.contains(.alt) { parts.append("ALT") }
        if chord.modifiers.contains(.shift) { parts.append("SHIFT") }
        if chord.modifiers.contains(.meta) { parts.append("SUPER") }
        let key = chord.key.uppercased()
        switch key {
        case "SPACE", "RETURN", "ESCAPE", "TAB": parts.append(key.lowercased())
        default:
            guard key.count == 1 || (key.hasPrefix("F") && Int(key.dropFirst()) != nil) else { return nil }
            parts.append(key)
        }
        return parts.joined(separator: "+")
    }

    /// `a{sv}`, built entry by entry: GLib's variadic builders cannot be
    /// called from Swift, so every variant here is assembled from the typed
    /// constructors instead.
    private static func options(_ values: [String: String]) -> OpaquePointer {
        let builder = g_variant_builder_new(g_variant_type_new("a{sv}"))
        for (key, value) in values {
            let entry = g_variant_new_dict_entry(g_variant_new_string(key),
                                                 g_variant_new_variant(g_variant_new_string(value)))
            g_variant_builder_add_value(builder, entry)
        }
        let result = g_variant_builder_end(builder)!
        g_variant_builder_unref(builder)
        return result
    }

    private static func tuple(_ children: [OpaquePointer?]) -> OpaquePointer {
        var values = children
        return values.withUnsafeMutableBufferPointer { buffer in
            g_variant_new_tuple(buffer.baseAddress, gsize(buffer.count))!
        }
    }

    /// The Request path the portal will answer on, which is derived from the
    /// connection's unique name and the token we chose.
    private static func requestPath(on connection: OpaquePointer, token: String) -> String {
        let unique = String(cString: g_dbus_connection_get_unique_name(connection))
        let sender = unique.dropFirst().replacingOccurrences(of: ".", with: "_")
        return "/org/freedesktop/portal/desktop/request/\(sender)/\(token)"
    }

    private func subscribeResponse(on connection: OpaquePointer, path: String, box: ResponseBox) -> UInt32 {
        g_dbus_connection_signal_subscribe(
            connection,
            "org.freedesktop.portal.Desktop",
            "org.freedesktop.portal.Request",
            "Response",
            path,
            nil,
            GDBusSignalFlags(rawValue: 0),
            { _, _, _, _, _, parameters, user in
                guard let user, let parameters else { return }
                let box = Unmanaged<ResponseBox>.fromOpaque(user).takeUnretainedValue()
                var response: UInt32 = 1
                if let code = g_variant_get_child_value(parameters, 0) {
                    response = g_variant_get_uint32(code)
                    g_variant_unref(code)
                }
                let results = g_variant_get_child_value(parameters, 1)
                box.fire(response, results)
                if let results { g_variant_unref(results) }
            },
            Unmanaged.passRetained(box).toOpaque(),
            { user in
                guard let user else { return }
                Unmanaged<ResponseBox>.fromOpaque(user).release()
            })
    }

    private static func string(in results: OpaquePointer?, key: String) -> String? {
        guard let results else { return nil }
        guard let value = g_variant_lookup_value(results, key, nil) else { return nil }
        defer { g_variant_unref(value) }
        guard let raw = g_variant_get_string(value, nil) else { return nil }
        return String(cString: raw)
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write(Data("openmila: portal hotkeys: \(message)\n".utf8))
    }

    deinit {
        if let connection, activatedSubscription != 0 {
            g_dbus_connection_signal_unsubscribe(connection, activatedSubscription)
        }
        if let loop { g_main_loop_quit(loop) }
    }
}

/// Boxes, because a GDBus callback carries one opaque pointer and Swift
/// closures are not that.
private final class ResponseBox {
    private let body: (UInt32, OpaquePointer?) -> Void
    init(_ body: @escaping (UInt32, OpaquePointer?) -> Void) { self.body = body }
    func fire(_ response: UInt32, _ results: OpaquePointer?) { body(response, results) }
}

private final class ActivatedBox {
    private let body: (String) -> Void
    init(_ body: @escaping (String) -> Void) { self.body = body }
    func fire(_ id: String) { body(id) }
}
#endif
