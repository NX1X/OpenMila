// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

#if os(Linux)
import CSecret
import Foundation
import PlatformKit

/// Secrets in the desktop's own keyring through the Secret Service, which is
/// what upstream gets from the macOS Keychain. GNOME Keyring, KWallet and
/// KeePassXC all implement it; libsecret talks to whichever is running.
///
/// Only the non-variadic entry points are used, because Swift cannot call C
/// variadics: the schema is built with `secret_schema_newv` and the attributes
/// are passed as a `GHashTable`.
///
/// A machine with no running Secret Service is normal (a bare X session, a
/// container, a server), so callers pair this with `FileSecretStore` through
/// `LinuxSecretStore`.
public struct SecretServiceStore: SecretStore {
    public enum Error: Swift.Error, LocalizedError {
        case badKey
        case service(String)

        public var errorDescription: String? {
            switch self {
            case .badKey: return "That key cannot be stored."
            case .service(let message): return "The system keyring refused the request. \(message)"
            }
        }
    }

    /// The attribute every entry is filed under, so one key maps to one item.
    private static let attributeName = "openmila-key"
    private static let schemaName = "io.github.nx1x.openmila"

    private let label: String

    public init(label: String = "OpenMila") { self.label = label }

    /// True when a Secret Service answers on the session bus. Used to decide
    /// between this store and the file fallback, once, at startup.
    public static var isAvailable: Bool {
        let store = SecretServiceStore()
        // A lookup for a key that does not exist succeeds (returning nothing)
        // when the service is there, and fails when it is not.
        do {
            _ = try store.lookup(key: "openmila-availability-probe")
            return true
        } catch {
            return false
        }
    }

    // MARK: SecretStore

    public func save(key: String, value: String) throws {
        guard !key.isEmpty else { throw Error.badKey }
        guard !value.isEmpty else { try delete(key: key); return }
        try withSchemaAndAttributes(key: key) { schema, attributes in
            var error: UnsafeMutablePointer<GError>?
            let ok = secret_password_storev_sync(schema, attributes, SECRET_COLLECTION_DEFAULT,
                                                 "\(label): \(key)", value, nil, &error)
            try Self.check(ok, error)
        }
    }

    public func load(key: String) -> String? {
        try? lookup(key: key)
    }

    public func delete(key: String) throws {
        guard !key.isEmpty else { throw Error.badKey }
        try withSchemaAndAttributes(key: key) { schema, attributes in
            var error: UnsafeMutablePointer<GError>?
            let ok = secret_password_clearv_sync(schema, attributes, nil, &error)
            // Clearing something that is not there returns false with no
            // error, which is success as far as a caller is concerned.
            if error != nil { try Self.check(ok, error) }
        }
    }

    public func isAbsent(key: String) -> Bool {
        (try? lookup(key: key)) as? String == nil
    }

    // MARK: libsecret plumbing

    private func lookup(key: String) throws -> String? {
        var result: String?
        try withSchemaAndAttributes(key: key) { schema, attributes in
            var error: UnsafeMutablePointer<GError>?
            guard let password = secret_password_lookupv_sync(schema, attributes, nil, &error) else {
                try Self.check(1, error)   // no value, but the service answered
                return
            }
            result = String(cString: password)
            secret_password_free(password)
        }
        return result
    }

    /// Builds the schema and the one-attribute table, runs `body`, and frees
    /// both however it ends.
    private func withSchemaAndAttributes(key: String,
                                         // GHashTable is an incomplete C type, so Swift sees pointers
                                         // to it as OpaquePointer.
                                         _ body: (UnsafePointer<SecretSchema>?, OpaquePointer?) throws -> Void) throws {
        guard let types = g_hash_table_new_full(g_str_hash, g_str_equal, { g_free($0) }, nil) else {
            throw Error.service("out of memory")
        }
        defer { g_hash_table_unref(types) }
        g_hash_table_insert(types, g_strdup(Self.attributeName),
                            UnsafeMutableRawPointer(bitPattern: Int(SECRET_SCHEMA_ATTRIBUTE_STRING.rawValue)))

        guard let schema = secret_schema_newv(Self.schemaName, SECRET_SCHEMA_NONE, types) else {
            throw Error.service("the schema could not be built")
        }
        defer { secret_schema_unref(schema) }

        guard let attributes = g_hash_table_new_full(g_str_hash, g_str_equal, { g_free($0) }, { g_free($0) }) else {
            throw Error.service("out of memory")
        }
        defer { g_hash_table_unref(attributes) }
        g_hash_table_insert(attributes, g_strdup(Self.attributeName), g_strdup(key))

        try body(UnsafePointer(schema), attributes)
    }

    private static func check(_ ok: gboolean, _ error: UnsafeMutablePointer<GError>?) throws {
        if let error {
            let message = String(cString: error.pointee.message)
            g_error_free(error)
            throw Error.service(message)
        }
        if ok == 0 { throw Error.service("the keyring reported a failure") }
    }
}

/// The secret store the Linux platform hands out: the desktop keyring when one
/// is running and working, and files with owner-only permissions when it is
/// not.
///
/// "Working" cannot be decided once at startup. A container has libsecret and
/// a session bus but no keyring daemon behind it, so the lookup that probes
/// for a service succeeds while the first write fails; CI found exactly that.
/// So the keyring is tried, and the first failure of any kind moves this store
/// to files for the rest of the session. Secrets never end up split across the
/// two: a value is only ever written to one, and reads try the keyring first,
/// then the files.
public final class LinuxSecretStore: SecretStore, @unchecked Sendable {
    private let keyring = SecretServiceStore()
    private let files: FileSecretStore
    private let lock = NSLock()
    private var keyringUsable: Bool

    public init(fallbackDirectory: URL) {
        files = FileSecretStore(directory: fallbackDirectory)
        keyringUsable = SecretServiceStore.isAvailable
    }

    /// True while the keyring is still in use. Diagnostics report it so a user
    /// can see where their keys went.
    public var usesKeyring: Bool { lock.withLock { keyringUsable } }

    private func demoteKeyring(_ error: Swift.Error) {
        lock.withLock { keyringUsable = false }
        FileHandle.standardError.write(Data(
            "openmila: the system keyring refused a request, falling back to files for this session (\(error))\n".utf8))
    }

    public func save(key: String, value: String) throws {
        if usesKeyring {
            do {
                try keyring.save(key: key, value: value)
                return
            } catch {
                demoteKeyring(error)
            }
        }
        try files.save(key: key, value: value)
    }

    public func load(key: String) -> String? {
        if usesKeyring, let value = keyring.load(key: key) { return value }
        return files.load(key: key)
    }

    public func delete(key: String) throws {
        // Both, so a value written before a demotion cannot survive a delete.
        if usesKeyring {
            do { try keyring.delete(key: key) } catch { demoteKeyring(error) }
        }
        try files.delete(key: key)
    }

    public func isAbsent(key: String) -> Bool {
        load(key: key) == nil
    }
}
#endif
