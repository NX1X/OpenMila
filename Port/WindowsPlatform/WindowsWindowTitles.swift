// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Windows only.
#if os(Windows)

import Foundation
import WinSDK

/// Collects titles from the `EnumWindows` callback, which cannot capture.
private final class TitleBox {
    var titles: [String] = []
}

/// File scope, not a static member: naming a static from inside the callback
/// captures the enclosing metatype, and a C function pointer cannot be formed
/// from a closure that captures anything at all.
private let windowTitleLimit = 4096

/// Reads the captions of the top-level windows on this desktop.
///
/// The Windows twin of `X11WindowTitles`, and the reason the port's meeting
/// detection is not weaker here than upstream's: a meeting in a browser tab
/// has no process of its own, so the only thing that names it is the window
/// caption. Windows hands any application every top-level window's caption, so
/// unlike a Wayland session there is nothing to work around.
///
/// `GetWindowTextW` on another process's window returns the cached caption
/// rather than sending it `WM_GETTEXT`, so a hung window cannot hang this.
public enum WindowsWindowTitles {
    /// Cap matching the X11 reader: a desktop has tens of windows, and a
    /// thousands-long walk means something is wrong, not that there is more to
    /// read.
    static var limit: Int { windowTitleLimit }

    /// Every visible top-level window's caption, empty ones dropped.
    public static func all() -> [String] {
        let box = TitleBox()
        let context = Unmanaged.passUnretained(box).toOpaque()
        _ = EnumWindows({ window, parameter in
            // LPARAM is a signed pointer-sized integer, so the pointer comes
            // back through Int rather than through UInt: on Windows the
            // unsigned round trip has no exact overload.
            guard let window, let raw = UnsafeMutableRawPointer(bitPattern: Int(parameter))
            else { return true }
            let box = Unmanaged<TitleBox>.fromOpaque(raw).takeUnretainedValue()
            // false stops the enumeration, which is what the cap wants.
            guard box.titles.count < windowTitleLimit else { return false }
            // WindowsBool is its own type, not Bool: compare rather than
            // assume a conversion the overlay does not offer.
            guard IsWindowVisible(window) != false else { return true }
            let length = GetWindowTextLengthW(window)
            guard length > 0 else { return true }
            var buffer = [WCHAR](repeating: 0, count: Int(length) + 1)
            let copied = GetWindowTextW(window, &buffer, Int32(buffer.count))
            guard copied > 0 else { return true }
            box.titles.append(String(decoding: buffer.prefix(Int(copied)), as: UTF16.self))
            return true
        }, LPARAM(Int(bitPattern: context)))
        return box.titles
    }
}
#endif
