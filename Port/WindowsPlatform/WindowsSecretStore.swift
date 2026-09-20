// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

#if os(Windows)
import Foundation
import PlatformKit
import WinSDK

/// Secrets encrypted with DPAPI and written under the app's data directory.
/// DPAPI keys the ciphertext to the signed-in Windows account, so another
/// account (or the same files copied elsewhere) cannot read them. Upstream:
/// `KeychainHelper` over the macOS Keychain.
public struct WindowsSecretStore: SecretStore {
    public enum Error: Swift.Error { case badKey, encryptFailed, writeFailed }

    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    func url(for key: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !key.isEmpty, let name = key.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return directory.appendingPathComponent(name + ".dpapi")
    }

    public func save(key: String, value: String) throws {
        guard let url = url(for: key) else { throw Error.badKey }
        guard !value.isEmpty else { try delete(key: key); return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var plain = Array(value.utf8)
        var output = DATA_BLOB()
        // The blob must point at the buffer for the whole call, so it is
        // built inside the closure that owns the pointer. szDataDescr is nil:
        // it is only a label Windows shows in credential dialogs, and
        // CRYPTPROTECT_UI_FORBIDDEN means no dialog is ever shown.
        let ok = plain.withUnsafeMutableBufferPointer { buffer -> Bool in
            var input = DATA_BLOB(cbData: DWORD(buffer.count), pbData: buffer.baseAddress)
            return CryptProtectData(&input, nil, nil, nil, nil,
                                    DWORD(CRYPTPROTECT_UI_FORBIDDEN), &output)
        }
        guard ok, let bytes = output.pbData else { throw Error.encryptFailed }
        defer { LocalFree(bytes) }
        let data = Data(bytes: bytes, count: Int(output.cbData))
        try data.write(to: url, options: .atomic)
    }

    public func load(key: String) -> String? {
        guard let url = url(for: key), var data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data.withUnsafeMutableBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            var input = DATA_BLOB(cbData: DWORD(raw.count), pbData: base.assumingMemoryBound(to: BYTE.self))
            var output = DATA_BLOB()
            guard CryptUnprotectData(&input, nil, nil, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), &output),
                  let bytes = output.pbData else { return nil }
            defer { LocalFree(bytes) }
            return String(data: Data(bytes: bytes, count: Int(output.cbData)), encoding: .utf8)
        }
    }

    public func delete(key: String) throws {
        guard let url = url(for: key) else { throw Error.badKey }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
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
