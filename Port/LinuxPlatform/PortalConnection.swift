// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only.
#if os(Linux)

import CGio
import Foundation

/// The bits of the XDG portal protocol every portal shares.
///
/// A portal call does not answer: it returns a Request object path, and the
/// answer arrives later as a Response signal on that path. Each portal then
/// adds its own methods on top. This type owns a session bus connection, a
/// GMainContext to pump it, and the request-and-wait dance, so that
/// GlobalShortcuts and RemoteDesktop can each be about what they actually do.
final class PortalConnection {
    let connection: OpaquePointer
    private let context: OpaquePointer

    static let busName = "org.freedesktop.portal.Desktop"
    static let objectPath = "/org/freedesktop/portal/desktop"

    /// Opens a connection with its own context, so pumping it cannot disturb
    /// whatever main loop the application itself is running.
    init?() {
        guard let context = g_main_context_new() else { return nil }
        g_main_context_push_thread_default(context)
        var error: UnsafeMutablePointer<GError>?
        guard let connection = g_bus_get_sync(G_BUS_TYPE_SESSION, nil, &error) else {
            if let error { g_error_free(error) }
            g_main_context_pop_thread_default(context)
            g_main_context_unref(context)
            return nil
        }
        self.context = context
        self.connection = connection
    }

    deinit {
        g_main_context_pop_thread_default(context)
        g_main_context_unref(context)
    }

    /// Whether a portal interface exists at all, asked through its version
    /// property, which is the cheapest question available.
    static func implements(_ interface: String) -> Bool {
        guard let portal = PortalConnection() else { return false }
        var error: UnsafeMutablePointer<GError>?
        let reply = g_dbus_connection_call_sync(
            portal.connection, busName, objectPath,
            "org.freedesktop.DBus.Properties", "Get",
            variantTuple([g_variant_new_string(interface), g_variant_new_string("version")]),
            nil, GDBusCallFlags(rawValue: 0), 2000, nil, &error)
        if let error { g_error_free(error); return false }
        if let reply { g_variant_unref(reply) }
        return true
    }

    /// Calls a portal method that answers with a Request, waits for the
    /// Response signal, and returns its results dictionary. The caller owns
    /// the returned variant.
    ///
    /// `arguments` must already contain the options dictionary carrying
    /// `handle_token`, because only the caller knows where in its signature
    /// that belongs.
    func request(interface: String, method: String, token: String,
                 arguments: OpaquePointer, timeout: TimeInterval) -> (response: UInt32, results: OpaquePointer?) {
        var answered: UInt32 = 1
        var results: OpaquePointer?
        let waiter = DispatchSemaphore(value: 0)

        let box = PortalResponseBox { code, dictionary in
            answered = code
            // Retained so it outlives the callback; the caller unrefs it.
            if let dictionary { results = g_variant_ref(dictionary) }
            waiter.signal()
        }
        let subscription = g_dbus_connection_signal_subscribe(
            connection, Self.busName, "org.freedesktop.portal.Request", "Response",
            requestPath(token: token), nil, GDBusSignalFlags(rawValue: 0),
            { _, _, _, _, _, parameters, user in
                guard let user, let parameters else { return }
                let box = Unmanaged<PortalResponseBox>.fromOpaque(user).takeUnretainedValue()
                var code: UInt32 = 1
                if let first = g_variant_get_child_value(parameters, 0) {
                    code = g_variant_get_uint32(first)
                    g_variant_unref(first)
                }
                let dictionary = g_variant_get_child_value(parameters, 1)
                box.fire(code, dictionary)
                if let dictionary { g_variant_unref(dictionary) }
            },
            Unmanaged.passRetained(box).toOpaque(),
            { user in
                guard let user else { return }
                Unmanaged<PortalResponseBox>.fromOpaque(user).release()
            })
        defer { g_dbus_connection_signal_unsubscribe(connection, subscription) }

        var error: UnsafeMutablePointer<GError>?
        let reply = g_dbus_connection_call_sync(
            connection, Self.busName, Self.objectPath, interface, method, arguments,
            nil, GDBusCallFlags(rawValue: 0), 30000, nil, &error)
        if let error {
            Self.report("\(method) failed: \(String(cString: error.pointee.message))")
            g_error_free(error)
            return (1, nil)
        }
        if let reply { g_variant_unref(reply) }

        // The answer arrives on this thread's context, so it has to be pumped
        // rather than merely waited on.
        let deadline = Date().addingTimeInterval(timeout)
        while waiter.wait(timeout: .now() + .milliseconds(20)) == .timedOut, Date() < deadline {
            while g_main_context_iteration(context, 0) != 0 {}
        }
        return (answered, results)
    }

    /// A portal method that answers immediately rather than with a Request.
    @discardableResult
    func call(interface: String, method: String, arguments: OpaquePointer) -> Bool {
        var error: UnsafeMutablePointer<GError>?
        let reply = g_dbus_connection_call_sync(
            connection, Self.busName, Self.objectPath, interface, method, arguments,
            nil, GDBusCallFlags(rawValue: 0), 5000, nil, &error)
        if let error {
            Self.report("\(method) failed: \(String(cString: error.pointee.message))")
            g_error_free(error)
            return false
        }
        if let reply { g_variant_unref(reply) }
        return true
    }

    /// The path the portal will answer on, derived from this connection's
    /// unique name and the token the caller chose.
    func requestPath(token: String) -> String {
        let unique = String(cString: g_dbus_connection_get_unique_name(connection))
        let sender = unique.dropFirst().replacingOccurrences(of: ".", with: "_")
        return "/org/freedesktop/portal/desktop/request/\(sender)/\(token)"
    }

    static func token(_ prefix: String = "openmila") -> String {
        "\(prefix)_\(UInt32.random(in: 1...UInt32.max))"
    }

    static func report(_ message: String) {
        FileHandle.standardError.write(Data("openmila: portal: \(message)\n".utf8))
    }
}

/// `a{sv}` from string values, built without GLib's variadic builders, which
/// Swift cannot call.
func variantOptions(_ values: [String: OpaquePointer]) -> OpaquePointer {
    let builder = g_variant_builder_new(g_variant_type_new("a{sv}"))
    for (key, value) in values {
        g_variant_builder_add_value(builder,
                                    g_variant_new_dict_entry(g_variant_new_string(key),
                                                             g_variant_new_variant(value)))
    }
    let result = g_variant_builder_end(builder)!
    g_variant_builder_unref(builder)
    return result
}

func variantOptions(_ values: [String: String]) -> OpaquePointer {
    variantOptions(values.mapValues { g_variant_new_string($0)! })
}

func variantTuple(_ children: [OpaquePointer?]) -> OpaquePointer {
    var values = children
    return values.withUnsafeMutableBufferPointer { buffer in
        g_variant_new_tuple(buffer.baseAddress, gsize(buffer.count))!
    }
}

func variantString(in results: OpaquePointer?, key: String) -> String? {
    guard let results, let value = g_variant_lookup_value(results, key, nil) else { return nil }
    defer { g_variant_unref(value) }
    guard let raw = g_variant_get_string(value, nil) else { return nil }
    return String(cString: raw)
}

/// A box, because a GDBus callback carries one opaque pointer and a Swift
/// closure is not that.
final class PortalResponseBox {
    private let body: (UInt32, OpaquePointer?) -> Void
    init(_ body: @escaping (UInt32, OpaquePointer?) -> Void) { self.body = body }
    func fire(_ response: UInt32, _ results: OpaquePointer?) { body(response, results) }
}
#endif
