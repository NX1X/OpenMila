// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import DefaultBackend
import Foundation
import SwiftCrossUI
@testable import Mila

@main
struct OpenMilaApp: App {
    let model = AppModel()

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
                Button("About \(AppIdentity.name)") {
                    model.platform.notifier.notify(
                        title: "\(AppIdentity.name) \(AppIdentity.version)",
                        body: "A port of Mila \(AppIdentity.upstreamVersion) by Uri Harduf at Island. Not affiliated with Island Technology, Inc.")
                }
            }
        }
    }
}
