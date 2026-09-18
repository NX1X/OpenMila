// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// `import SwiftUI` off macOS, for upstream's non-view files only.
//
// Two upstream model files (`MeetingApp`, `SpeakerColor`) import SwiftUI just
// to name a `Color`. This shim provides that one value type so they compile
// unchanged. It is NOT a UI toolkit: OpenMila's views are written against
// SwiftCrossUI, which converts from these components at the view boundary.

/// An sRGB colour with opacity, mirroring the slice of `SwiftUI.Color`
/// upstream's model layer uses.
public struct Color: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public func opacity(_ opacity: Double) -> Color {
        Color(red: red, green: green, blue: blue, opacity: self.opacity * opacity)
    }
}

/// Named colours, using the light-appearance sRGB values of the matching
/// system colours so a speaker keeps the same hue users see in Mila.
extension Color {
    public static let blue = Color(red: 0.0, green: 0.478, blue: 1.0)
    public static let green = Color(red: 0.204, green: 0.78, blue: 0.349)
    public static let orange = Color(red: 1.0, green: 0.584, blue: 0.0)
    public static let purple = Color(red: 0.686, green: 0.322, blue: 0.871)
    public static let pink = Color(red: 1.0, green: 0.176, blue: 0.333)
    public static let teal = Color(red: 0.188, green: 0.69, blue: 0.78)
    public static let indigo = Color(red: 0.345, green: 0.337, blue: 0.839)
    public static let brown = Color(red: 0.635, green: 0.518, blue: 0.369)
    public static let red = Color(red: 1.0, green: 0.231, blue: 0.188)
    public static let yellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    public static let gray = Color(red: 0.557, green: 0.557, blue: 0.576)
    public static let white = Color(red: 1, green: 1, blue: 1)
    public static let black = Color(red: 0, green: 0, blue: 0)
    public static let clear = Color(red: 0, green: 0, blue: 0, opacity: 0)
}
