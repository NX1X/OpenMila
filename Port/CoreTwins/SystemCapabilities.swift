// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `Mila/Models/SystemCapabilities.swift` (IOKit + sysctl on
// macOS). Same fields and the same single decision, read from the OS instead.
//
// Upstream gates Live AI off on MacBook Air class machines, which cannot run
// whisper and pyannote together in real time. There is no "Air" elsewhere, so
// the equivalent here is a capacity floor: fewer than 8 logical cores or less
// than 12 GB of RAM counts as the constrained class.

import Foundation

struct SystemCapabilities: Sendable, Equatable {
    let modelIdentifier: String
    let marketingName: String
    /// Kept for source compatibility with upstream call sites and tests. Off
    /// macOS it means "constrained machine", by the floor described above.
    let isMacBookAir: Bool
    let physicalRamGB: Int
    let performanceCoreCount: Int

    var isLiveAIRecommended: Bool { !isMacBookAir }

    static let live: SystemCapabilities = .readFromHardware()

    static let minimumCoresForLiveAI = 8
    static let minimumRamGBForLiveAI = 12

    static func isConstrained(cores: Int, ramGB: Int) -> Bool {
        // Unknown values (0) must not gate a feature off: upstream's rule is
        // "unknown hardware, don't gate".
        let lowCores = cores > 0 && cores < minimumCoresForLiveAI
        let lowRam = ramGB > 0 && ramGB < minimumRamGBForLiveAI
        return lowCores || lowRam
    }

    static func readFromHardware() -> SystemCapabilities {
        let info = ProcessInfo.processInfo
        let ramGB = Int((Double(info.physicalMemory) / 1_073_741_824.0).rounded())
        let cores = info.activeProcessorCount
        return SystemCapabilities(
            modelIdentifier: Self.machineModel(),
            marketingName: Self.machineModel(),
            isMacBookAir: isConstrained(cores: cores, ramGB: ramGB),
            physicalRamGB: ramGB,
            performanceCoreCount: cores
        )
    }

    private static func machineModel() -> String {
        #if os(Linux)
        let path = "/sys/devices/virtual/dmi/id/product_name"
        let name = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return ""
        #endif
    }
}
