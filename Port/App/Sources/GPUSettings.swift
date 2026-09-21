// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Whether OpenMila hands the model to the graphics card. A port-only setting:
// Mila has no equivalent because every Mac it supports has Metal, so there is
// nothing to decide there.

import Foundation
import TranscriptionCore

/// Persisted in the same namespaced style as upstream's settings objects.
/// `TranscriptionCore` owns the flag the engine reads, so this type is only
/// the storage plus one line of glue, applied at launch before any model is
/// loaded.
final class GPUSettings {
    private enum Keys {
        static let enabled = "gpu.enabled"
    }

    private let defaults: UserDefaults

    /// Default on: a machine with a usable device should use it without being
    /// asked, and the probe already refuses a software device.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            apply()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        apply()
    }

    private func apply() {
        VulkanAvailability.userDisabledGPU = !isEnabled
    }

    /// What the machine has, and what the app is doing about it.
    var summary: String { VulkanAvailability.summary }

    /// True when turning the switch on would change anything - there is no
    /// point offering a GPU to a machine that has none.
    var hasUsableDevice: Bool { VulkanAvailability.device.isUsableGPU }
}
