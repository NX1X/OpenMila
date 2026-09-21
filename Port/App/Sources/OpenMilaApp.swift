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
    }

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
