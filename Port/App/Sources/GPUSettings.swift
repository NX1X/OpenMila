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
        static let deviceName = "gpu.deviceName"
    }

    /// What the picker offers, in the order it offers it.
    static let automaticLabel = "Automatic (best device)"

    private let defaults: UserDefaults

    /// Default on: a machine with a usable device should use it without being
    /// asked, and the probe already refuses a software device.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            apply()
        }
    }

    /// The device the user picked, by name; `nil` is automatic. Stored by name
    /// rather than index because an index moves when hardware or a driver
    /// changes, and quietly using a different card than the one chosen would be
    /// worse than falling back to the best one.
    var deviceName: String? {
        didSet {
            if let deviceName { defaults.set(deviceName, forKey: Keys.deviceName) }
            else { defaults.removeObject(forKey: Keys.deviceName) }
            apply()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        self.deviceName = defaults.string(forKey: Keys.deviceName)
        apply()
    }

    private func apply() {
        VulkanAvailability.userDisabledGPU = !isEnabled
        VulkanAvailability.preferredGPUName = deviceName
    }

    /// Every device on this machine, for the picker.
    var devices: [VulkanAvailability.GPU] { VulkanAvailability.gpus }

    /// The label the picker should show as selected.
    var selectedLabel: String {
        guard let deviceName, devices.contains(where: { $0.name == deviceName }) else {
            return Self.automaticLabel
        }
        return deviceName
    }

    /// Picker labels: automatic first, then one per device with its kind, so a
    /// user with two cards can tell them apart.
    var deviceLabels: [String] {
        [Self.automaticLabel] + devices.map(\.name)
    }

    func choose(label: String) {
        deviceName = label == Self.automaticLabel ? nil : label
    }

    /// What the machine has, and what the app is doing about it.
    var summary: String { VulkanAvailability.summary }

    /// True when turning the switch on would change anything - there is no
    /// point offering a GPU to a machine that has none.
    var hasUsableDevice: Bool { !VulkanAvailability.gpus.isEmpty }
}
