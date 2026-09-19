// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// The seam between the portable core and each operating system. Every
// protocol names the upstream, Apple-bound type it stands in for, so a change
// upstream has an obvious counterpart here. Implementations live in
// `LinuxPlatform` and `WindowsPlatform`.

import Foundation

// MARK: Dictation

/// A key plus modifiers, independent of any OS key-code table. Upstream's
/// `HotkeyBinding` stores Carbon virtual key codes, which mean nothing
/// elsewhere.
public struct HotkeyChord: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let alt = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        /// Windows key / Super. Stands where Command does on macOS.
        public static let meta = Modifiers(rawValue: 1 << 3)
    }

    /// Layout-independent key name: "A"..."Z", "0"..."9", "F1"..."F24",
    /// "Space", "Return", "Escape", "Tab".
    public var key: String
    public var modifiers: Modifiers

    public init(key: String, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public var displayName: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.alt) { parts.append("Alt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.meta) { parts.append("Super") }
        parts.append(key)
        return parts.joined(separator: "+")
    }
}

public enum HotkeyRegistrationResult: Equatable, Sendable {
    case registered
    /// Another application or the desktop owns the combination.
    case unavailable
    /// The desktop asks the user to confirm shortcuts itself (XDG portal), so
    /// the binding the user ends up with may differ from the one requested.
    case delegatedToDesktop
}

/// Upstream: `HotkeyManager` (Carbon `RegisterEventHotKey`).
public protocol GlobalHotkeys: AnyObject, Sendable {
    func register(id: String, chord: HotkeyChord, onPressed: @escaping @Sendable () -> Void)
        async -> HotkeyRegistrationResult
    func unregister(id: String) async
    /// Probe without keeping the registration. Upstream validates a newly
    /// captured combination this way before persisting it.
    func canRegister(_ chord: HotkeyChord) async -> Bool
    /// Release everything while the settings UI captures a new combination.
    func suspendAll() async
    func resumeAll() async
}

public enum TextInjectionOutcome: Equatable, Sendable {
    /// Typed or pasted into the focused application.
    case injected
    /// The OS does not allow synthetic input here (Wayland without the
    /// RemoteDesktop portal). The text is on the clipboard; tell the user.
    case leftOnClipboard
    case failed(String)
}

/// Upstream: `DictationController.paste` (NSPasteboard + CGEvent Cmd+V) and
/// `AccessibilityPermission`.
public protocol TextInjector: Sendable {
    func inject(_ text: String) async -> TextInjectionOutcome
}

// MARK: System services

/// Upstream: `KeychainHelper`. `isAbsent` is true only on positive proof that
/// the item is gone; a read error is not proof.
public protocol SecretStore: Sendable {
    func save(key: String, value: String) throws
    func load(key: String) -> String?
    func delete(key: String) throws
    func isAbsent(key: String) -> Bool
}

/// Upstream: `SleepGuard` (IOPMAssertion). Hold while recording.
public protocol SleepInhibitor: AnyObject, Sendable {
    func acquire(reason: String)
    func release()
}

/// Upstream: app-support paths via `FileManager` and `Bundle.main` resources.
public protocol AppPaths: Sendable {
    /// Recordings index, models, settings sidecars. XDG data dir / %APPDATA%.
    var dataDirectory: URL { get }
    var cacheDirectory: URL { get }
    var logDirectory: URL { get }
    /// Read-only files shipped with the app (VAD model, diarization models,
    /// the connection-test sample clip).
    func resource(named name: String) -> URL?
}

public struct AvailableUpdate: Equatable, Sendable {
    public let version: String
    public let isPrerelease: Bool
    public let releaseNotesMarkdown: String
    public let downloadPage: URL

    public init(version: String, isPrerelease: Bool, releaseNotesMarkdown: String, downloadPage: URL) {
        self.version = version
        self.isPrerelease = isPrerelease
        self.releaseNotesMarkdown = releaseNotesMarkdown
        self.downloadPage = downloadPage
    }
}

/// Upstream: Sparkle via `UpdaterViewModel`. The beta channel is the release's
/// prerelease flag; a client that has not opted in must never be offered one.
public protocol Updater: Sendable {
    func check(includePrereleases: Bool) async throws -> AvailableUpdate?
}

/// Upstream: `NSSound.beep()` and user-facing alerts raised off the main window.
public protocol Notifier: Sendable {
    func beep()
    func notify(title: String, body: String)
}

/// Upstream: `DirectoryWatcher` (FSEvents), driving the Voice Memos importer.
/// Here it drives watched-folder import.
public protocol FolderWatcher: AnyObject, Sendable {
    func start(directory: URL, onChange: @escaping @Sendable () -> Void) throws
    func stop()
}

public struct DetectedMeeting: Hashable, Sendable {
    public let appName: String
    /// Matches upstream's `MeetingApp` raw values: "zoom", "teams", "googleMeet".
    public let appKey: String

    public init(appName: String, appKey: String) {
        self.appName = appName
        self.appKey = appKey
    }
}

/// Upstream: `MeetingDetector` (Core Audio process taps + window titles).
public protocol MeetingSignals: Sendable {
    func activeMeetings() async -> [DetectedMeeting]
}

/// Upstream: `SecurityFrameworkSignatureVerifier`. Must fail closed.
public protocol BinaryTrust: Sendable {
    /// True only when the file is signed by the expected publisher.
    func isTrusted(executable: URL, expectedPublisher: String) -> Bool
}

/// Everything a platform provides, handed to the app at launch.
public struct PlatformServices: Sendable {
    public let microphone: MicrophoneCapture
    public let appAudio: AppAudioCapture?
    public let hotkeys: GlobalHotkeys?
    public let textInjector: TextInjector?
    public let secrets: SecretStore
    public let sleep: SleepInhibitor
    public let paths: AppPaths
    public let updater: Updater?
    public let notifier: Notifier
    public let meetings: MeetingSignals?
    public let binaryTrust: BinaryTrust

    public init(microphone: MicrophoneCapture, appAudio: AppAudioCapture?, hotkeys: GlobalHotkeys?,
                textInjector: TextInjector?, secrets: SecretStore, sleep: SleepInhibitor,
                paths: AppPaths, updater: Updater?, notifier: Notifier,
                meetings: MeetingSignals?, binaryTrust: BinaryTrust) {
        self.microphone = microphone
        self.appAudio = appAudio
        self.hotkeys = hotkeys
        self.textInjector = textInjector
        self.secrets = secrets
        self.sleep = sleep
        self.paths = paths
        self.updater = updater
        self.notifier = notifier
        self.meetings = meetings
        self.binaryTrust = binaryTrust
    }
}
