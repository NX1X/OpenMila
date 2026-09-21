// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only.
#if os(Linux)

import CGio
import Foundation

/// Reads window titles from the accessibility bus, which works on Wayland.
///
/// Wayland refuses to let one client see another client's windows, so
/// `X11WindowTitles` returns nothing on a pure Wayland session and a meeting in
/// a browser tab (Google Meet, Proton Meet) cannot be found by title. The
/// accessibility stack is the way through: AT-SPI is how Orca reads any
/// application, it runs over D-Bus rather than over the display protocol, and
/// both Firefox and Chromium publish their window names there. No extension, no
/// portal dialog, no screen capture permission.
///
/// The tree is `registry root -> one accessible per application -> that
/// application's windows`, and a window's `Name` property is its title. Two
/// levels of children, one property each, all on the a11y bus.
///
/// It is not free and it is not always available: the accessibility bus exists
/// only when the desktop has accessibility support switched on, and an
/// application populates its tree lazily. `status` says which of those is the
/// case so the app can tell the user what to turn on instead of silently
/// finding no meetings.
public enum ATSPIWindowTitles {
    public enum Status: Equatable, Sendable {
        case ready
        /// The bus exists but the desktop has accessibility support off, so
        /// applications do not publish their trees.
        case accessibilityDisabled
        case unavailable(reason: String)

        public var description: String {
            switch self {
            case .ready:
                return "the accessibility bus answers"
            case .accessibilityDisabled:
                return "accessibility support is off, so no application publishes its windows"
            case .unavailable(let reason):
                return "no accessibility bus (\(reason))"
            }
        }
    }

    static let registryBus = "org.a11y.atspi.Registry"
    static let rootPath = "/org/a11y/atspi/accessible/root"
    static let accessible = "org.a11y.atspi.Accessible"
    static let properties = "org.freedesktop.DBus.Properties"

    /// Applications and windows to walk before giving up. A desktop has tens of
    /// each; a four-figure walk means something is wrong rather than that there
    /// is more to read. Each is one blocking D-Bus call, so these caps are what
    /// bound the cost.
    static let applicationLimit = 64
    static let windowLimit = 256
    static let callTimeoutMilliseconds: Int32 = 400

    /// Whether the titles this reader can see are worth asking for.
    public static var status: Status {
        guard let connection = Connection() else {
            return .unavailable(reason: "org.a11y.Bus did not answer")
        }
        return connection.isAccessibilityEnabled ? .ready : .accessibilityDisabled
    }

    /// Every window title the accessibility bus will name, or an empty list
    /// when it will not name any. Never throws: a title signal that fails is a
    /// missing signal, not an error the user can act on mid-recording.
    public static func all() -> [String] {
        guard let connection = Connection() else { return [] }
        var titles: [String] = []
        for application in connection.children(of: Self.registryBus, path: Self.rootPath,
                                               limit: applicationLimit) {
            for window in connection.children(of: application.bus, path: application.path,
                                              limit: windowLimit) {
                guard let name = connection.name(of: window), !name.isEmpty else { continue }
                titles.append(name)
                if titles.count >= windowLimit { return titles }
            }
        }
        return titles
    }

    // MARK: The bus

    /// A connection to the accessibility bus, which is a second bus with its
    /// own address: the session bus only tells you where it is.
    final class Connection {
        private let context: OpaquePointer
        private let connection: OpaquePointer

        init?() {
            guard let context = g_main_context_new() else { return nil }
            g_main_context_push_thread_default(context)
            guard let address = Self.busAddress(),
                  let connection = Self.connect(to: address) else {
                g_main_context_pop_thread_default(context)
                g_main_context_unref(context)
                return nil
            }
            self.context = context
            self.connection = connection
        }

        deinit {
            g_object_unref(UnsafeMutableRawPointer(connection))
            g_main_context_pop_thread_default(context)
            g_main_context_unref(context)
        }

        /// `org.a11y.Bus.GetAddress` on the session bus.
        private static func busAddress() -> String? {
            var error: UnsafeMutablePointer<GError>?
            guard let session = g_bus_get_sync(G_BUS_TYPE_SESSION, nil, &error) else {
                if let error { g_error_free(error) }
                return nil
            }
            defer { g_object_unref(UnsafeMutableRawPointer(session)) }
            let reply = g_dbus_connection_call_sync(
                session, "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress",
                nil, g_variant_type_new("(s)"), GDBusCallFlags(rawValue: 0),
                ATSPIWindowTitles.callTimeoutMilliseconds, nil, &error)
            if let error { g_error_free(error); return nil }
            guard let reply else { return nil }
            defer { g_variant_unref(reply) }
            guard let child = g_variant_get_child_value(reply, 0) else { return nil }
            defer { g_variant_unref(child) }
            guard let raw = g_variant_get_string(child, nil) else { return nil }
            let address = String(cString: raw)
            return address.isEmpty ? nil : address
        }

        private static func connect(to address: String) -> OpaquePointer? {
            var error: UnsafeMutablePointer<GError>?
            let connection = address.withCString { cAddress in
                // AUTHENTICATION_CLIENT (1<<0) | MESSAGE_BUS_CONNECTION (1<<3)
                // from gioenums.h. The constants are not imported by name, and
                // both are required: the a11y bus is a message bus that
                // expects us to authenticate as a client.
                g_dbus_connection_new_for_address_sync(
                    cAddress, GDBusConnectionFlags(rawValue: (1 << 0) | (1 << 3)),
                    nil, nil, &error)
            }
            if let error { g_error_free(error); return nil }
            return connection
        }

        /// `org.a11y.Status.IsEnabled` on the session bus: the desktop-wide
        /// switch (`gsettings set org.gnome.desktop.interface toolkit-accessibility true`).
        /// False means applications will not populate a tree, so a walk would
        /// find nothing and the reason would be invisible.
        var isAccessibilityEnabled: Bool {
            var error: UnsafeMutablePointer<GError>?
            guard let session = g_bus_get_sync(G_BUS_TYPE_SESSION, nil, &error) else {
                if let error { g_error_free(error) }
                return false
            }
            defer { g_object_unref(UnsafeMutableRawPointer(session)) }
            let reply = g_dbus_connection_call_sync(
                session, "org.a11y.Bus", "/org/a11y/bus", "org.freedesktop.DBus.Properties", "Get",
                variantTuple([g_variant_new_string("org.a11y.Status"),
                              g_variant_new_string("IsEnabled")]),
                nil, GDBusCallFlags(rawValue: 0),
                ATSPIWindowTitles.callTimeoutMilliseconds, nil, &error)
            if let error { g_error_free(error); return false }
            guard let reply else { return false }
            defer { g_variant_unref(reply) }
            guard let boxed = g_variant_get_child_value(reply, 0) else { return false }
            defer { g_variant_unref(boxed) }
            guard let value = g_variant_get_variant(boxed) else { return false }
            defer { g_variant_unref(value) }
            return g_variant_get_boolean(value) != 0
        }

        /// `GetChildren` on an accessible: each child is a (bus name, object
        /// path) pair, because the tree spans processes.
        func children(of bus: String, path: String, limit: Int) -> [(bus: String, path: String)] {
            var error: UnsafeMutablePointer<GError>?
            let reply = g_dbus_connection_call_sync(
                connection, bus, path, ATSPIWindowTitles.accessible, "GetChildren",
                nil, g_variant_type_new("(a(so))"), GDBusCallFlags(rawValue: 0),
                ATSPIWindowTitles.callTimeoutMilliseconds, nil, &error)
            if let error { g_error_free(error); return [] }
            guard let reply else { return [] }
            defer { g_variant_unref(reply) }
            guard let array = g_variant_get_child_value(reply, 0) else { return [] }
            defer { g_variant_unref(array) }
            var found: [(bus: String, path: String)] = []
            let count = min(Int(g_variant_n_children(array)), limit)
            for index in 0..<count {
                guard let entry = g_variant_get_child_value(array, gsize(index)) else { continue }
                defer { g_variant_unref(entry) }
                guard let busValue = g_variant_get_child_value(entry, 0),
                      let pathValue = g_variant_get_child_value(entry, 1) else { continue }
                defer { g_variant_unref(busValue); g_variant_unref(pathValue) }
                guard let rawBus = g_variant_get_string(busValue, nil),
                      let rawPath = g_variant_get_string(pathValue, nil) else { continue }
                let childBus = String(cString: rawBus)
                let childPath = String(cString: rawPath)
                // The registry names the root of each application with an empty
                // bus, which would address this process instead.
                guard !childBus.isEmpty, !childPath.isEmpty else { continue }
                found.append((bus: childBus, path: childPath))
            }
            return found
        }

        /// An accessible's `Name`, which for a window is its title.
        func name(of object: (bus: String, path: String)) -> String? {
            var error: UnsafeMutablePointer<GError>?
            let reply = g_dbus_connection_call_sync(
                connection, object.bus, object.path, ATSPIWindowTitles.properties, "Get",
                variantTuple([g_variant_new_string(ATSPIWindowTitles.accessible),
                              g_variant_new_string("Name")]),
                nil, GDBusCallFlags(rawValue: 0),
                ATSPIWindowTitles.callTimeoutMilliseconds, nil, &error)
            if let error { g_error_free(error); return nil }
            guard let reply else { return nil }
            defer { g_variant_unref(reply) }
            guard let boxed = g_variant_get_child_value(reply, 0) else { return nil }
            defer { g_variant_unref(boxed) }
            guard let value = g_variant_get_variant(boxed) else { return nil }
            defer { g_variant_unref(value) }
            guard let raw = g_variant_get_string(value, nil) else { return nil }
            return String(cString: raw)
        }
    }
}
#endif
