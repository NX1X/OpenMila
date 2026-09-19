// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `Mila/Models/KeychainHelper.swift` (macOS Keychain). Same four
// calls, same semantics, including `isAbsent` being true only on positive
// proof of absence.
//
// This is the FALLBACK store: one file per secret under the user's data
// directory, directory 0700 and files 0600, written atomically. The platform
// layer supersedes it with the Secret Service on Linux and DPAPI on Windows.
// Windows has no POSIX mode bits to lean on, so until DPAPI lands secrets are
// not persisted there at all: `save` does nothing and `load` returns nil,
// which the app already treats as "no key configured".

import Foundation

enum KeychainHelper {
    /// Overridable so tests never touch the real store.
    static var directoryOverride: URL?

    static var directory: URL {
        if let directoryOverride { return directoryOverride }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share")
        return base.appendingPathComponent("openmila/secrets", isDirectory: true)
    }

    /// Keys are identifiers such as `remote.apiKey`. Anything outside a
    /// conservative alphabet is percent-encoded so a key can never name a path
    /// outside the secrets directory.
    static func fileURL(for key: String) -> URL? {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !key.isEmpty,
              let name = key.addingPercentEncoding(withAllowedCharacters: allowed),
              !name.isEmpty else { return nil }
        return directory.appendingPathComponent(name + ".secret", isDirectory: false)
    }

    static func save(key: String, value: String) {
        #if os(Windows)
        return
        #else
        guard let url = fileURL(for: key) else { return }
        // Same contract as upstream: an empty value deletes the item.
        guard !value.isEmpty, let data = value.data(using: .utf8) else {
            delete(key: key)
            return
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            // Create with 0600 BEFORE any secret byte is written, so the value
            // is never on disk under a wider mode.
            let staging = directory.appendingPathComponent(UUID().uuidString + ".tmp")
            guard fm.createFile(atPath: staging.path, contents: nil,
                                attributes: [.posixPermissions: 0o600]) else { return }
            let handle = try FileHandle(forWritingTo: staging)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: url)
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Never log the value or the key's contents. A failed save leaves
            // the previous secret (if any) in place.
        }
        #endif
    }

    static func load(key: String) -> String? {
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    static func delete(key: String) {
        guard let url = fileURL(for: key) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func isAbsent(key: String) -> Bool {
        guard let url = fileURL(for: key) else { return true }
        // `fileExists` answers false for "cannot look" as well as "not there",
        // so confirm the directory itself is readable before trusting it.
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return false }
        var isDir: ObjCBool = false
        let dirExists = fm.fileExists(atPath: directory.path, isDirectory: &isDir)
        if !dirExists { return true }
        return isDir.boolValue && fm.isReadableFile(atPath: directory.path)
    }
}
