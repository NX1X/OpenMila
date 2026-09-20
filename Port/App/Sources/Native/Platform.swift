// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Cross-platform front for the native pieces in GtkExtras.swift (Linux) and
// their WinUI counterparts (Windows). Views call these; each platform decides
// how to render them. Where a platform has no implementation yet, the view is
// left as it is, so nothing breaks.

import Foundation
import SwiftCrossUI

/// Upstream's SF Symbols, mapped to freedesktop / Adwaita symbolic icon names.
enum AppIcon {
    static let home = "go-home-symbolic"                      // house
    static let list = "view-list-symbolic"                    // list.bullet.rectangle
    static let folder = "folder-symbolic"                     // folder
    static let dictation = "audio-input-microphone-symbolic"  // mic
    static let trash = "user-trash-symbolic"                  // trash
    static let record = "media-record-symbolic"               // record.circle
    static let stop = "media-playback-stop-symbolic"          // stop.fill
    static let pause = "media-playback-pause-symbolic"        // pause.fill
    static let play = "media-playback-start-symbolic"         // play.fill
    static let settings = "emblem-system-symbolic"            // gearshape
    static let about = "help-about-symbolic"                  // info.circle
    static let warning = "dialog-warning-symbolic"            // exclamationmark.triangle
    static let sparkles = "starred-symbolic"                  // sparkles
}

#if !os(Linux)
struct ContextMenuItem {
    let title: String
    let isDestructive: Bool
    let action: () -> Void
    init(_ title: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isDestructive = destructive
        self.action = action
    }
}
#endif

/// An icon from the platform's own icon set.
struct PlatformIcon: View {
    let name: String
    init(_ name: String) { self.name = name }

    var body: some View {
        #if os(Linux)
        SystemIcon(name: name)
        #else
        EmptyView()
        #endif
    }
}

extension View {
    func platformContextMenu(_ items: [ContextMenuItem]) -> some View {
        #if os(Linux)
        return contextMenu(items)
        #else
        return self
        #endif
    }

    func platformDragSource(_ id: UUID) -> some View {
        #if os(Linux)
        return recordingDragSource(id)
        #else
        return self
        #endif
    }

    @ViewBuilder
    func platformDropTarget(enabled: Bool, _ onDrop: @escaping (UUID) -> Void) -> some View {
        #if os(Linux)
        if enabled { recordingDropTarget(onDrop) } else { self }
        #else
        self
        #endif
    }
}
