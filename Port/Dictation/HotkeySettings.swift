// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Port twin of `Mila/Dictation/HotkeySettings.swift`. Upstream persists Carbon
// key codes under `hotkeys.*`; those mean nothing here, so the port keeps its
// own keys (`openmila.hotkeys.*`) holding layout-independent chords.
// Defaults: Ctrl+Alt+2 (English) and Ctrl+Alt+3 (Hebrew), the same digits as
// Mila's Cmd+2 / Cmd+3 with the modifier desktops leave free.

import Combine
import Foundation
import PlatformKit

@MainActor
public final class HotkeySettings: ObservableObject {
    @Published public private(set) var chords: [DictationLanguage: HotkeyChord] = [:]
    @Published public private(set) var registration: [DictationLanguage: HotkeyRegistrationResult] = [:]

    private let defaults: UserDefaults
    private let hotkeys: GlobalHotkeys?
    private var onPressed: ((DictationLanguage) -> Void)?

    public static let defaults: [DictationLanguage: HotkeyChord] = [
        .english: HotkeyChord(key: "2", modifiers: [.control, .alt]),
        .hebrew: HotkeyChord(key: "3", modifiers: [.control, .alt]),
    ]

    public init(defaults: UserDefaults = .standard, hotkeys: GlobalHotkeys?) {
        self.defaults = defaults
        self.hotkeys = hotkeys
        for language in DictationLanguage.allCases {
            if let data = defaults.data(forKey: Self.key(language)),
               let chord = try? JSONDecoder().decode(HotkeyChord.self, from: data) {
                chords[language] = chord
            } else {
                chords[language] = Self.defaults[language]
            }
        }
    }

    public var isAvailable: Bool { hotkeys != nil }

    public func chord(for language: DictationLanguage) -> HotkeyChord {
        chords[language] ?? Self.defaults[language]!
    }

    /// Install the handler and register every chord.
    public func activate(onPressed: @escaping (DictationLanguage) -> Void) async {
        self.onPressed = onPressed
        for language in DictationLanguage.allCases { await register(language) }
    }

    public func setChord(_ chord: HotkeyChord, for language: DictationLanguage) async -> Bool {
        if let hotkeys, await !hotkeys.canRegister(chord) { return false }
        chords[language] = chord
        if let data = try? JSONEncoder().encode(chord) { defaults.set(data, forKey: Self.key(language)) }
        await register(language)
        return true
    }

    public func resetToDefault(_ language: DictationLanguage) async {
        _ = await setChord(Self.defaults[language]!, for: language)
    }

    public func suspendAll() async { await hotkeys?.suspendAll() }
    public func resumeAll() async { await hotkeys?.resumeAll() }

    private func register(_ language: DictationLanguage) async {
        guard let hotkeys, let onPressed else { return }
        let result = await hotkeys.register(id: language.hotkeyID, chord: chord(for: language)) {
            Task { @MainActor in onPressed(language) }
        }
        registration[language] = result
    }

    private static func key(_ language: DictationLanguage) -> String { "openmila.hotkeys.\(language.rawValue)" }
}

extension HotkeyChord {
    /// Parses "Ctrl+Alt+2", "Super+Shift+Space", case-insensitive.
    public static func parse(_ text: String) -> HotkeyChord? {
        var modifiers: Modifiers = []
        var key: String?
        for part in text.split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part.lowercased() {
            case "ctrl", "control": modifiers.insert(.control)
            case "alt", "option": modifiers.insert(.alt)
            case "shift": modifiers.insert(.shift)
            case "super", "meta", "win", "cmd": modifiers.insert(.meta)
            case "": continue
            default:
                guard key == nil else { return nil }
                key = part.count == 1 ? part.uppercased() : part.prefix(1).uppercased() + part.dropFirst().lowercased()
            }
        }
        guard let key, !modifiers.isEmpty else { return nil }
        return HotkeyChord(key: key, modifiers: modifiers)
    }
}
