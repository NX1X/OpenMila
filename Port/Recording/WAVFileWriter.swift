// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import Foundation

/// Streams mono Float32 samples into a WAV file, the way upstream's
/// `AVAudioFile` does for `RecordingSession`: the header goes down first with
/// placeholder sizes, frames are appended as they arrive, and the sizes are
/// patched on `close()`. A crash leaves a file with the placeholder sizes,
/// which upstream's `WAVHeaderRepair` fixes on the next launch, so this
/// writer uses the exact 44-byte canonical layout that repair code expects.
public final class WAVFileWriter {
    public enum Error: Swift.Error { case cannotCreate(URL), closed }

    public let url: URL
    public let sampleRate: UInt32
    private let handle: FileHandle
    private var dataBytes: UInt32 = 0
    private var isOpen = true

    public private(set) var frameCount: Int = 0

    public init(url: URL, sampleRate: UInt32 = 16_000) throws {
        self.url = url
        self.sampleRate = sampleRate
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        guard fm.createFile(atPath: url.path, contents: nil) else { throw Error.cannotCreate(url) }
        handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Self.header(sampleRate: sampleRate, dataBytes: 0))
    }

    public func write(_ samples: [Float]) throws {
        guard isOpen else { throw Error.closed }
        guard !samples.isEmpty else { return }
        var data = Data(capacity: samples.count * 4)
        samples.withUnsafeBufferPointer { data.append($0) }
        try handle.write(contentsOf: data)
        dataBytes += UInt32(data.count)
        frameCount += samples.count
    }

    /// Patch the sizes and close. Idempotent.
    public func close() throws {
        guard isOpen else { return }
        isOpen = false
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Self.header(sampleRate: sampleRate, dataBytes: dataBytes))
        try handle.synchronize()
        try handle.close()
    }

    deinit { try? close() }

    static func header(sampleRate: UInt32, dataBytes: UInt32) -> Data {
        var data = Data(capacity: 44)
        func le<T: FixedWidthInteger>(_ value: T) {
            Swift.withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8)); le(UInt32(36) &+ dataBytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); le(UInt32(16))
        le(UInt16(3)); le(UInt16(1)); le(sampleRate); le(sampleRate * 4); le(UInt16(4)); le(UInt16(32))
        data.append(contentsOf: Array("data".utf8)); le(dataBytes)
        return data
    }
}
