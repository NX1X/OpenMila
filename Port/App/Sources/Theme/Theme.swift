// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Mila's theme tokens, measured from upstream's views (docs/port/STYLE.md).
// Colours are sRGB, matching the light-appearance values users see in Mila.

import SwiftCrossUI

enum Theme {
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let secondaryText = Color(red: 0.55, green: 0.55, blue: 0.58)
    static let danger = Color(red: 1.0, green: 0.231, blue: 0.188)
    static let recording = Color(red: 1.0, green: 0.231, blue: 0.188)
    static let success = Color(red: 0.204, green: 0.78, blue: 0.349)

    /// Upstream's `SpeakerColor` palette order.
    static let speakers: [Color] = [
        Color(red: 0.0, green: 0.478, blue: 1.0), Color(red: 0.204, green: 0.78, blue: 0.349), Color(red: 1.0, green: 0.584, blue: 0.0),
        Color(red: 0.686, green: 0.322, blue: 0.871), Color(red: 1.0, green: 0.176, blue: 0.333), Color(red: 0.188, green: 0.69, blue: 0.78),
        Color(red: 0.345, green: 0.337, blue: 0.839), Color(red: 0.635, green: 0.518, blue: 0.369),
    ]

    static func speakerColor(_ label: String) -> Color {
        let index: Int
        if label.hasPrefix("SPEAKER_"), let n = Int(label.dropFirst("SPEAKER_".count)), n >= 0 {
            index = n
        } else {
            index = abs(label.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        }
        return speakers[index % speakers.count]
    }

    static let sidebarMinWidth = 230
    static let windowMinWidth = 1000
    static let windowMinHeight = 620
}

/// Icon names from an open set (Lucide), mapped from the SF Symbols upstream
/// uses. Text labels are used until the icon set is bundled.
enum Icon {
    static let record = "mic"
    static let stop = "square"
    static let pause = "pause"
    static let play = "play"
    static let folder = "folder"
    static let trash = "trash-2"
    static let settings = "settings"
    static let sparkles = "sparkles"
}
