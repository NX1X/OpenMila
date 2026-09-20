// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Linux only.
#if os(Linux)

import CX11
import Foundation

/// Reads the titles of the windows on an X display.
///
/// Upstream spots Google Meet by looking at browser window titles, because a
/// meeting in a tab has no process of its own to find. That is possible on
/// X11, including XWayland, where any client may walk the window tree. It is
/// deliberately impossible on Wayland: a client cannot see another client's
/// windows at all, which is why Meet detection is an X11-only signal and the
/// port says so rather than pretending otherwise.
public enum X11WindowTitles {
    /// Every window title on the default display, or an empty list when there
    /// is no X display to ask.
    public static func all() -> [String] {
        guard let display = XOpenDisplay(nil) else { return [] }
        defer { XCloseDisplay(display) }

        let root = XDefaultRootWindow(display)
        let netName = XInternAtom(display, "_NET_WM_NAME", 0)
        let utf8String = XInternAtom(display, "UTF8_STRING", 0)

        var titles: [String] = []
        var queue: [Window] = [root]
        // A desktop has a few hundred windows at most; the cap is there so a
        // pathological tree cannot make a background poll expensive.
        var visited = 0
        while let window = queue.popLast(), visited < 4096 {
            visited += 1
            if let title = title(of: window, on: display, netName: netName, utf8String: utf8String),
               !title.isEmpty {
                titles.append(title)
            }
            var rootReturn: Window = 0
            var parentReturn: Window = 0
            var children: UnsafeMutablePointer<Window>?
            var count: UInt32 = 0
            guard XQueryTree(display, window, &rootReturn, &parentReturn, &children, &count) != 0,
                  let children else { continue }
            for index in 0..<Int(count) { queue.append(children[index]) }
            XFree(children)
        }
        return titles
    }

    /// `_NET_WM_NAME` first, which is UTF-8 and what modern toolkits set;
    /// `WM_NAME` second, which is Latin-1 and what older clients set.
    private static func title(of window: Window, on display: OpaquePointer,
                              netName: Atom, utf8String: Atom) -> String? {
        var actualType: Atom = 0
        var actualFormat: Int32 = 0
        var itemCount: UInt = 0
        var bytesAfter: UInt = 0
        var data: UnsafeMutablePointer<UInt8>?

        if XGetWindowProperty(display, window, netName, 0, 1024, 0, utf8String,
                              &actualType, &actualFormat, &itemCount, &bytesAfter, &data) == 0,
           let data, itemCount > 0 {
            defer { XFree(data) }
            return String(decoding: UnsafeBufferPointer(start: data, count: Int(itemCount)), as: UTF8.self)
        }
        if let data { XFree(data) }

        var name: UnsafeMutablePointer<CChar>?
        guard XFetchName(display, window, &name) != 0, let name else { return nil }
        defer { XFree(name) }
        return String(cString: name)
    }
}
#endif
