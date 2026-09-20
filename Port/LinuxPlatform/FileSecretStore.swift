// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only: this module is the Linux platform layer, and SwiftPM
// builds every target in the package on every OS, including a Windows
// `swift test`.
#if os(Linux)

import Foundation
import PlatformKit

/// Per-secret files with 0600 permissions under the data directory. The same
/// scheme as the core's `KeychainHelper` twin, exposed through the platform
/// protocol. The Secret Service (libsecret) backend replaces this later; the
/// on-disk layout is deliberately shared so the swap migrates nothing.
public struct FileSecretStore: SecretStore {
    public enum Error: Swift.Error { case badKey, writeFailed }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    func url(for key: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !key.isEmpty, let name = key.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return directory.appendingPathComponent(name + ".secret")
    }

    public func save(key: String, value: String) throws {
        guard let url = url(for: key) else { throw Error.badKey }
        guard !value.isEmpty else { try delete(key: key); return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let staging = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        guard fm.createFile(atPath: staging.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw Error.writeFailed
        }
        let handle = try FileHandle(forWritingTo: staging)
        try handle.write(contentsOf: Data(value.utf8))
        try handle.synchronize()
        try handle.close()
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: url)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func load(key: String) -> String? {
        guard let url = url(for: key), let data = try? Data(contentsOf: url),
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    public func delete(key: String) throws {
        guard let url = url(for: key) else { throw Error.badKey }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func isAbsent(key: String) -> Bool {
        guard let url = url(for: key) else { return true }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return false }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir) else { return true }
        return isDir.boolValue && fm.isReadableFile(atPath: directory.path)
    }
}
#endif
