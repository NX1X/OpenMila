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

    /// Probed once: the answer cannot change while the process runs, and the
    /// probe creates and destroys a Vulkan instance, which is not free.
    public static let device: Device = probe()

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

    private static func probe() -> Device {
        if ProcessInfo.processInfo.environment["OPENMILA_DISABLE_GPU"] == "1" {
            return .none(reason: "OPENMILA_DISABLE_GPU=1")
        }
        // The loader is opened by name at run time, never linked, so a build
        // with the Vulkan backend still runs where Vulkan is absent. The two
        // systems spell that differently and nothing else here differs.
        #if os(Windows)
        let libraryName = "vulkan-1.dll"
        guard let library = LoadLibraryW(libraryName.withCString(encodedAs: UTF16.self) { $0 }) else {
            return .none(reason: "\(libraryName) is not installed")
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
            return .none(reason: "\(libraryName) is not installed")
        }
        defer { dlclose(library) }
        let symbol: (String) -> UnsafeMutableRawPointer? = { dlsym(library, $0) }
        #endif

        guard let createSymbol = symbol("vkCreateInstance"),
              let enumerateSymbol = symbol("vkEnumeratePhysicalDevices"),
              let propertiesSymbol = symbol("vkGetPhysicalDeviceProperties"),
              let destroySymbol = symbol("vkDestroyInstance") else {
            return .none(reason: "the Vulkan loader is missing its entry points")
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
            return .none(reason: "no Vulkan driver answered")
        }
        defer { destroy(instance, nil) }

        var count: UInt32 = 0
        guard enumerate(instance, &count, nil) == 0, count > 0 else {
            return .none(reason: "the driver reports no devices")
        }
        var handles = [UnsafeMutableRawPointer?](repeating: nil, count: Int(count))
        guard handles.withUnsafeMutableBufferPointer({ buffer in
            enumerate(instance, &count, buffer.baseAddress)
        }) == 0 else {
            return .none(reason: "the device list could not be read")
        }

        // VkPhysicalDeviceProperties: apiVersion, driverVersion, vendorID and
        // deviceID are four uint32s, then deviceType, then a 256-byte name.
        var best: Device = .none(reason: "the device list was empty")
        for handle in handles.compactMap({ $0 }) {
            var storage = [UInt8](repeating: 0, count: 1024)
            storage.withUnsafeMutableBytes { raw in
                properties(handle, raw.baseAddress)
            }
            let type = storage.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt32.self) }
            let name = String(decoding: storage[20..<(20 + 256)].prefix { $0 != 0 }, as: UTF8.self)
            switch type {
            case 1: return .gpu(name: name, kind: "integrated GPU")
            case 2: return .gpu(name: name, kind: "discrete GPU")
            case 3: return .gpu(name: name, kind: "virtual GPU")
            case 4: best = .software(name: name)   // keep looking for a real one
            default: if case .none = best { best = .software(name: name) }
            }
        }
        return best
    }
}
#endif
