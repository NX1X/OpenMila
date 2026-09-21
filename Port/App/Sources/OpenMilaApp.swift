// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import DefaultBackend
import Foundation
import SwiftCrossUI
#if os(Windows)
import CWinShim
#endif
@testable import Mila

@main
struct OpenMilaApp: App {
    let model: AppModel

    init() {
        if CommandLine.arguments.contains("--version") {
            print("\(AppIdentity.name) \(AppIdentity.version) (Mila \(AppIdentity.upstreamVersion))")
            exit(0)
        }
        #if os(Windows)
        // Before any window exists: Windows groups a window under the shortcut
        // that launched it only when the process and the shortcut carry the
        // same AppUserModelID, and the installer stamps this one on both the
        // Start menu and desktop shortcuts. Failing is not worth reporting -
        // the only consequence is an ungrouped taskbar button.
        _ = Array(AppIdentity.appUserModelID.utf16 + [0]).withUnsafeBufferPointer {
            om_set_app_user_model_id($0.baseAddress)
        }
        #endif
        model = AppModel()
        #if os(Windows)
        // WinUI themes the inside of the window and nothing outside it, so a
        // dark app sat under a white caption bar. The bar is painted to match
        // once the first window exists, and again a little later in case the
        // toolkit created it after the first pass; both calls are cheap and
        // harmless when nothing changed. The colour follows Windows' own
        // apps-dark-mode switch, which is also what the toolkit reads.
        Task { @MainActor in
            for delay in [UInt64(300), 1500, 4000] {
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
                Self.matchTitleBarToTheme()
            }
        }
        #endif
    }

    #if os(Windows)
    static func matchTitleBarToTheme() {
        let dark = om_apps_use_dark_theme() != 0
        // 0x00BBGGRR: the theme's window background, so the caption reads as
        // part of the app rather than a strip of a different colour.
        let caption: UInt32 = dark ? Theme.windowsCaptionDark : Theme.windowsCaptionLight
        let text: UInt32 = dark ? 0x00F5F5F5 : 0x00202020
        _ = om_apply_title_bar_theme(dark ? 1 : 0, caption, text)
    }
    #endif

    var body: some Scene {
        WindowGroup(AppIdentity.name) {
            ContentView(model: model)
        }
        .defaultSize(width: Theme.windowMinWidth, height: Theme.windowMinHeight)
        .commands {
            CommandMenu("Recording") {
                Button("Start Microphone Recording") { try? model.startRecording(source: .microphone, appTarget: nil) }
                Button("Stop Recording") { model.stopRecording() }
            }
            CommandMenu("Help") {
                Button("About \(AppIdentity.name)") { model.ui.showAbout = true }
            }
        }
    }
}
