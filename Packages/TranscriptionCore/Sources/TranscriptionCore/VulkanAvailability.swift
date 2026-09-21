// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Added by NX1X for OpenMila; see CHANGES.md.
//
// Whether this machine has a graphics device worth handing the model to.
//
// On a Mac the question does not arise: every machine Mila supports has Metal,
// so whisper.cpp always uses the GPU. Off macOS a machine may have a discrete
// card, an integrated one, a virtual one, or nothing but a software
// implementation of Vulkan (llvmpipe, lavapipe, SwiftShader). That last case
// is the trap: the Vulkan loader answers, a "device" is enumerated, and
// running the model on it is SLOWER than the CPU backend, because it is the
// CPU pretending to be a GPU through a graphics API.
//
// So the port asks the Vulkan loader directly, at run time, through dlopen:
// no link-time dependency, so a build with the Vulkan backend still runs on a
// machine with no Vulkan at all, and no GPU is requested unless a real one
// answers.
#if !canImport(Metal)
import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import WinSDK
#endif

public enum VulkanAvailability {
    /// What the probe found, reported in diagnostics so a user can see why
    /// their machine is fast or slow.
    public enum Device: Equatable, Sendable {
        case none(reason: String)
        case software(name: String)
        case gpu(name: String, kind: String)

        /// Only a real graphics device earns the model.
        public var isUsableGPU: Bool {
            if case .gpu = self { return true }
            return false
        }

        public var description: String {
            switch self {
            case .none(let reason): return "no Vulkan device (\(reason))"
            case .software(let name): return "software Vulkan only (\(name)), using the CPU backend"
            case .gpu(let name, let kind): return "\(kind) (\(name))"
            }
        }
    }

    /// One graphics device the port would use.
    ///
    /// `index` is what whisper.cpp's `gpu_device` means: the position among
    /// GPU-type devices, in enumeration order, NOT the position in the full
    /// Vulkan device list. whisper.cpp counts only devices ggml reports as GPU
    /// or integrated GPU, and this list is built the same way, so the two agree
    /// on what "device 1" is.
    public struct GPU: Equatable, Sendable {
        public let index: Int
        public let name: String
        public let kind: String

        public init(index: Int, name: String, kind: String) {
            self.index = index
            self.name = name
            self.kind = kind
        }

        public var description: String { "\(kind) (\(name))" }
    }

    /// Probed once: the answer cannot change while the process runs, and the
    /// probe creates and destroys a Vulkan instance, which is not free.
    public static let probed: Probe = probe()

    /// Every usable graphics device, best first is NOT the order - enumeration
    /// order is, because the index has to match whisper.cpp's.
    public static var gpus: [GPU] { probed.gpus }

    /// The machine's answer, kept for the callers that only want one line.
    public static var device: Device { probed.best }

    /// The user's decision, which is a different thing from what the machine
    /// has. Vulkan drivers vary in quality, so someone who hits a driver bug
    /// needs a switch rather than a reinstall; `OPENMILA_DISABLE_GPU=1` is the
    /// same decision taken before the process starts. Set once at launch from
    /// the app's settings, read on every model load.
    nonisolated(unsafe) public static var userDisabledGPU = false

    /// Which device the user picked, by name. Names rather than indices,
    /// because an index moves when a card is added, removed or re-enumerated,
    /// and silently transcribing on a different card than the one chosen is
    /// worse than falling back. `nil` means automatic.
    ///
    /// `OPENMILA_GPU_NAME` is the same choice made before the process starts,
    /// for the CLI and for a headless machine with no Settings window. A choice
    /// made in the app wins over it.
    public static var preferredGPUName: String? {
        get { chosenGPUName ?? environmentGPUName }
        set { chosenGPUName = newValue }
    }

    nonisolated(unsafe) private static var chosenGPUName: String?

    private static var environmentGPUName: String? {
        let value = ProcessInfo.processInfo.environment["OPENMILA_GPU_NAME"]
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// The device the model will actually be handed to: the user's choice when
    /// it is still present, the best one otherwise.
    public static var selectedGPU: GPU? {
        guard !userDisabledGPU else { return nil }
        return select(among: gpus, preferring: preferredGPUName)
    }

    /// Discrete beats integrated beats virtual. A software device is never in
    /// `gpus`, so it can never be chosen by accident.
    public static var bestGPU: GPU? { best(among: gpus) }

    /// Pure, so the choice is testable on a machine with no Vulkan at all -
    /// which is every CI runner the port has.
    public static func best(among devices: [GPU]) -> GPU? {
        let rank: [String: Int] = ["discrete GPU": 0, "integrated GPU": 1, "virtual GPU": 2]
        return devices.min { (rank[$0.kind] ?? 9, $0.index) < (rank[$1.kind] ?? 9, $1.index) }
    }

    /// The user's pick when it is still there, the best device otherwise. A
    /// name that has disappeared falls back rather than failing: the card was
    /// removed or renamed by a driver update, and refusing to transcribe would
    /// be a worse answer than using the one that is present.
    public static func select(among devices: [GPU], preferring name: String?) -> GPU? {
        if let name, let match = devices.first(where: { $0.name == name }) { return match }
        return best(among: devices)
    }

    /// What whisper.cpp is actually asked for: a real device the user has not
    /// turned off.
    public static var usesGPU: Bool { selectedGPU != nil }

    /// `whisper_context_params.gpu_device`.
    public static var gpuDeviceIndex: Int32 { Int32(selectedGPU?.index ?? 0) }

    /// One line for Settings, the diagnostic report and the CLI, so all three
    /// say the same thing.
    public static var summary: String {
        if userDisabledGPU, device.isUsableGPU {
            return "\(device.description); turned off in Settings"
        }
        guard let selected = selectedGPU else { return device.description }
        var line = selected.description
        if gpus.count > 1 {
            line += "; \(gpus.count) devices found"
            if preferredGPUName == nil { line += ", chosen automatically" }
        }
        if let wanted = preferredGPUName, wanted != selected.name {
            line += "; \"\(wanted)\" is no longer present"
        }
        return line
    }

    /// What one probe found: every usable device, and the one-line answer.
    public struct Probe: Sendable {
        public let gpus: [GPU]
        public let best: Device
    }

    // MARK: The probe

    private static let instanceCreateInfoType: UInt32 = 1   // VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    private static let applicationInfoType: UInt32 = 0      // VK_STRUCTURE_TYPE_APPLICATION_INFO

    private struct ApplicationInfo {
        var sType: UInt32 = applicationInfoType
        var padding: UInt32 = 0
        var pNext: UnsafeRawPointer? = nil
        var pApplicationName: UnsafePointer<CChar>? = nil
        var applicationVersion: UInt32 = 0
        var pEngineName: UnsafePointer<CChar>? = nil
        var engineVersion: UInt32 = 0
        var apiVersion: UInt32 = 1 << 22   // VK_API_VERSION_1_0
    }

    private struct InstanceCreateInfo {
        var sType: UInt32 = instanceCreateInfoType
        var padding: UInt32 = 0
        var pNext: UnsafeRawPointer? = nil
        var flags: UInt32 = 0
        var padding2: UInt32 = 0
        var pApplicationInfo: UnsafeRawPointer? = nil
        var enabledLayerCount: UInt32 = 0
        var padding3: UInt32 = 0
        var ppEnabledLayerNames: UnsafeRawPointer? = nil
        var enabledExtensionCount: UInt32 = 0
        var padding4: UInt32 = 0
        var ppEnabledExtensionNames: UnsafeRawPointer? = nil
    }

    private typealias CreateInstance = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int32
    private typealias DestroyInstance = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void
    private typealias EnumerateDevices = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?, UnsafeMutableRawPointer?) -> Int32
    private typealias DeviceProperties = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

    private static func probe() -> Probe {
        Probe(gpus: found.gpus, best: found.best)
    }

    /// The probe proper. Split from `probe()` only so every early return can
    /// say "no devices" once rather than in five places.
    private static var found: (gpus: [GPU], best: Device) {
        func empty(_ reason: String) -> (gpus: [GPU], best: Device) {
            ([], .none(reason: reason))
        }
        if ProcessInfo.processInfo.environment["OPENMILA_DISABLE_GPU"] == "1" {
            return empty("OPENMILA_DISABLE_GPU=1")
        }
        // The loader is opened by name at run time, never linked, so a build
        // with the Vulkan backend still runs where Vulkan is absent. The two
        // systems spell that differently and nothing else here differs.
        #if os(Windows)
        let libraryName = "vulkan-1.dll"
        guard let library = LoadLibraryW(libraryName.withCString(encodedAs: UTF16.self) { $0 }) else {
            return empty("\(libraryName) is not installed")
        }
        defer { FreeLibrary(library) }
        // GetProcAddress hands back FARPROC, which Swift types as a function
        // taking nothing and returning Int64. Every symbol below is called
        // through its own signature, so the address is what matters.
        let symbol: (String) -> UnsafeMutableRawPointer? = { name in
            name.withCString { cName in
                guard let address = GetProcAddress(library, cName) else { return nil }
                return unsafeBitCast(address, to: UnsafeMutableRawPointer?.self)
            }
        }
        #else
        let libraryName = "libvulkan.so.1"
        guard let library = dlopen(libraryName, RTLD_NOW) else {
            return empty("\(libraryName) is not installed")
        }
        defer { dlclose(library) }
        let symbol: (String) -> UnsafeMutableRawPointer? = { dlsym(library, $0) }
        #endif

        guard let createSymbol = symbol("vkCreateInstance"),
              let enumerateSymbol = symbol("vkEnumeratePhysicalDevices"),
              let propertiesSymbol = symbol("vkGetPhysicalDeviceProperties"),
              let destroySymbol = symbol("vkDestroyInstance") else {
            return empty("the Vulkan loader is missing its entry points")
        }
        let createInstance = unsafeBitCast(createSymbol, to: CreateInstance.self)
        let enumerate = unsafeBitCast(enumerateSymbol, to: EnumerateDevices.self)
        let properties = unsafeBitCast(propertiesSymbol, to: DeviceProperties.self)
        let destroy = unsafeBitCast(destroySymbol, to: DestroyInstance.self)

        var application = ApplicationInfo()
        var instance: UnsafeMutableRawPointer?
        let created: Int32 = "OpenMila".withCString { name in
            application.pApplicationName = name
            return withUnsafePointer(to: &application) { applicationPointer -> Int32 in
                var info = InstanceCreateInfo()
                info.pApplicationInfo = UnsafeRawPointer(applicationPointer)
                return withUnsafePointer(to: &info) { infoPointer in
                    createInstance(UnsafeRawPointer(infoPointer), nil, &instance)
                }
            }
        }
        guard created == 0, let instance else {
            return empty("no Vulkan driver answered")
        }
        defer { destroy(instance, nil) }

        var count: UInt32 = 0
        guard enumerate(instance, &count, nil) == 0, count > 0 else {
            return empty("the driver reports no devices")
        }
        var handles = [UnsafeMutableRawPointer?](repeating: nil, count: Int(count))
        guard handles.withUnsafeMutableBufferPointer({ buffer in
            enumerate(instance, &count, buffer.baseAddress)
        }) == 0 else {
            return empty("the device list could not be read")
        }

        // VkPhysicalDeviceProperties: apiVersion, driverVersion, vendorID and
        // deviceID are four uint32s, then deviceType, then a 256-byte name.
        // Every device, not the first acceptable one: a laptop with an Intel
        // iGPU enumerated before an NVIDIA card would otherwise get the iGPU,
        // and a user with two cards could never pick the other.
        var gpus: [GPU] = []
        var software: String?
        for handle in handles.compactMap({ $0 }) {
            var storage = [UInt8](repeating: 0, count: 1024)
            storage.withUnsafeMutableBytes { raw in
                properties(handle, raw.baseAddress)
            }
            let type = storage.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt32.self) }
            let name = String(decoding: storage[20..<(20 + 256)].prefix { $0 != 0 }, as: UTF8.self)
            let kind: String?
            switch type {
            case 1: kind = "integrated GPU"
            case 2: kind = "discrete GPU"
            case 3: kind = "virtual GPU"
            default: kind = nil            // 4 is CPU, 0 is "other"
            }
            if let kind {
                // The index counts GPU-type devices only, which is what
                // whisper.cpp's gpu_device counts.
                gpus.append(GPU(index: gpus.count, name: name, kind: kind))
            } else if software == nil {
                software = name
            }
        }
        let rank: [String: Int] = ["discrete GPU": 0, "integrated GPU": 1, "virtual GPU": 2]
        if let best = gpus.min(by: { (rank[$0.kind] ?? 9, $0.index) < (rank[$1.kind] ?? 9, $1.index) }) {
            return (gpus, .gpu(name: best.name, kind: best.kind))
        }
        if let software {
            return ([], .software(name: software))
        }
        return empty("the driver reports no graphics device")
    }
}
#endif
