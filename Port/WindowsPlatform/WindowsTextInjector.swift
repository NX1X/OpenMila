// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

#if os(Windows)
import Foundation
import PlatformKit
import WinSDK

/// Puts text on the clipboard and sends Ctrl+V to the focused window, which is
/// what upstream does on macOS with NSPasteboard and a synthetic Cmd+V.
/// Windows has no accessibility permission for this, so it simply works.
public struct WindowsTextInjector: TextInjector {
    private let notifier: Notifier

    public init(notifier: Notifier) { self.notifier = notifier }

    public func inject(_ text: String) async -> TextInjectionOutcome {
        guard copyToClipboard(text) else { return .failed("Could not open the clipboard.") }
        guard sendPaste() else {
            notifier.notify(title: "Dictation ready", body: "The text is on the clipboard. Press Ctrl+V to paste it.")
            return .leftOnClipboard
        }
        return .injected
    }

    func copyToClipboard(_ text: String) -> Bool {
        var utf16 = Array(text.utf16)
        utf16.append(0)
        let bytes = utf16.count * MemoryLayout<UInt16>.size
        guard let handle = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(bytes)) else { return false }
        guard let buffer = GlobalLock(handle) else { GlobalFree(handle); return false }
        utf16.withUnsafeBytes { source in
            buffer.copyMemory(from: source.baseAddress!, byteCount: bytes)
        }
        GlobalUnlock(handle)
        guard OpenClipboard(nil) else { GlobalFree(handle); return false }
        defer { CloseClipboard() }
        EmptyClipboard()
        // On success the clipboard owns the memory; it must not be freed here.
        guard SetClipboardData(UINT(CF_UNICODETEXT), handle) != nil else {
            GlobalFree(handle)
            return false
        }
        return true
    }

    func sendPaste() -> Bool {
        var inputs = [INPUT](repeating: INPUT(), count: 4)
        func key(_ code: WORD, up: Bool) -> INPUT {
            var input = INPUT()
            input.type = DWORD(INPUT_KEYBOARD)
            input.ki.wVk = code
            input.ki.dwFlags = up ? DWORD(KEYEVENTF_KEYUP) : 0
            return input
        }
        inputs[0] = key(WORD(VK_CONTROL), up: false)
        inputs[1] = key(WORD(0x56), up: false)   // V
        inputs[2] = key(WORD(0x56), up: true)
        inputs[3] = key(WORD(VK_CONTROL), up: true)
        let sent = SendInput(UINT(inputs.count), &inputs, Int32(MemoryLayout<INPUT>.size))
        return sent == UINT(inputs.count)
    }
}
#endif
