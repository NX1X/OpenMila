// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only: this module is the Linux platform layer, and SwiftPM
// builds every target in the package on every OS, including a Windows
// `swift test`.
#if os(Linux)

import Foundation
import PlatformKit

/// Puts dictated text where the cursor is. Upstream pastes with a synthetic
/// Cmd+V after putting the text on the pasteboard.
///
/// Wayland does not let one application type into another without the
/// RemoteDesktop portal, so the honest default there is: text on the
/// clipboard, plus a notification telling the user to press Ctrl+V. Where a
/// typing tool is installed (`wtype` on Wayland, `xdotool` on X11) it is used
/// and the outcome is `.injected`.
public struct LinuxTextInjector: TextInjector {
    public enum Tool: String, CaseIterable { case wtype, xdotool, ydotool }

    private let environment: [String: String]
    private let notifier: Notifier
    /// The portal route, which is the only one a pure Wayland session has when
    /// no typing tool is installed. Built lazily: creating it asks the desktop
    /// a question, and there is no reason to ask before the first dictation.
    private let portal: PortalTextInjector?

    public init(notifier: Notifier,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                stateDirectory: URL? = nil) {
        self.notifier = notifier
        self.environment = environment
        if let stateDirectory {
            portal = PortalTextInjector(stateDirectory: stateDirectory)
        } else {
            portal = nil
        }
    }

    var isWayland: Bool { environment["XDG_SESSION_TYPE"] == "wayland" || environment["WAYLAND_DISPLAY"] != nil }

    /// Asks the desktop for permission to type, which shows a dialog. Meant
    /// for a Settings button; dictation never calls it.
    @discardableResult
    public func requestTypingPermission() -> Bool {
        guard isWayland, let portal, PortalTextInjector.isAvailable else { return false }
        return portal.requestPermission()
    }

    public var canTypeWithoutHelp: Bool {
        if availableTypingTool() != nil { return true }
        return isWayland && (portal?.isGranted ?? false)
    }

    public func inject(_ text: String) async -> TextInjectionOutcome {
        guard copyToClipboard(text) else {
            return .failed("Could not reach the clipboard (wl-copy or xclip missing).")
        }
        if let tool = availableTypingTool(), typeWith(tool, text: text) {
            return .injected
        }
        // No tool, or the tool failed. On Wayland the portal can still type,
        // once the user has allowed it; it never stops here to ask.
        if isWayland, let portal, PortalTextInjector.isAvailable, portal.paste() {
            return .injected
        }
        let hint = (isWayland && portal?.isGranted == false)
            ? "The text is on the clipboard. Press Ctrl+V to paste it, or allow typing in Settings to have it pasted for you."
            : "The text is on the clipboard. Press Ctrl+V to paste it."
        notifier.notify(title: "Dictation ready", body: hint)
        return .leftOnClipboard
    }

    func copyToClipboard(_ text: String) -> Bool {
        let candidates: [(String, [String])] = isWayland
            ? [("wl-copy", []), ("xclip", ["-selection", "clipboard"])]
            : [("xclip", ["-selection", "clipboard"]), ("xsel", ["--clipboard", "--input"]), ("wl-copy", [])]
        for (name, args) in candidates {
            guard let exe = Self.find(name, environment: environment) else { continue }
            let process = Process()
            process.executableURL = exe
            process.arguments = args
            let input = Pipe()
            process.standardInput = input
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                input.fileHandleForWriting.write(Data(text.utf8))
                try? input.fileHandleForWriting.close()
                // Clipboard tools stay alive to serve the selection (wl-copy
                // and xclip both fork for that), so waiting for exit hangs.
                // A launch that succeeded is the signal available.
                return true
            } catch { continue }
        }
        return false
    }

    func availableTypingTool() -> Tool? {
        let order: [Tool] = isWayland ? [.wtype, .ydotool] : [.xdotool, .ydotool]
        return order.first { Self.find($0.rawValue, environment: environment) != nil }
    }

    private func typeWith(_ tool: Tool, text: String) -> Bool {
        guard let exe = Self.find(tool.rawValue, environment: environment) else { return false }
        let process = Process()
        process.executableURL = exe
        switch tool {
        case .wtype: process.arguments = ["-M", "ctrl", "v", "-m", "ctrl"]
        case .xdotool: process.arguments = ["key", "--clearmodifiers", "ctrl+v"]
        case .ydotool: process.arguments = ["key", "29:1", "47:1", "47:0", "29:0"]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch { return false }
    }

    static func find(_ name: String, environment: [String: String]) -> URL? {
        for dir in (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":") {
            let url = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}
#endif
