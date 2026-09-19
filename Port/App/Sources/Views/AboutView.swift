// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// OpenMila's About screen. Mila's own credits page (Mila/Resources/Credits.html)
// is an HTML fragment for the macOS About panel and lists macOS components
// (Sparkle, the whisper xcframework); this screen gives the same credit to
// Mila's author and lists what OpenMila's builds actually contain.

import Foundation
import SwiftCrossUI

struct AboutView: View {
    @Binding var isPresented: Bool
    @Environment(\.openURL) var openURL

    func link(_ title: String, _ url: String) -> some View {
        Button(title) { if let u = URL(string: url) { openURL(u) } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppIdentity.name).font(.title2)
                Text("Version \(AppIdentity.version), based on Mila \(AppIdentity.upstreamVersion)")
                    .font(.callout).foregroundColor(Theme.secondaryText)

                Text("Mila was created by Uri Harduf at Island, and released as open source under the Apache License 2.0. OpenMila brings it to Linux and Windows. Thank you, Uri and Island, for building Mila and sharing it.")
                    .font(.body)
                HStack {
                    link("Mila on GitHub", "https://github.com/island-io/mila")
                    link("Island", "https://www.island.io/")
                    link("Uri Harduf", "https://github.com/urisland")
                }

                Text("OpenMila is an independent community port. It is not affiliated with or endorsed by Island Technology, Inc.")
                    .font(.caption).foregroundColor(Theme.secondaryText)

                Divider()
                Text("Ported and maintained by NX1X").font(.headline)
                HStack {
                    link("OpenMila on GitHub", "https://github.com/\(AppIdentity.repository)")
                    link("Report a problem", "https://github.com/\(AppIdentity.repository)/issues")
                    link("Contact", "https://nx1xlab.dev/contact")
                }

                Divider()
                Text("Built with").font(.headline)
                Text("""
                whisper.cpp (MIT), local Whisper inference
                Whisper models by OpenAI (MIT) and ivrit.ai (Apache-2.0), downloaded on first use
                Silero VAD (MIT) and pyannote speaker models (MIT, CC-BY-4.0)
                SwiftCrossUI (MIT), miniaudio (MIT-0), OpenCombine (MIT)
                swift-log and swift-crypto (Apache-2.0), the MCP Swift SDK
                The Swift runtime (Apache-2.0)
                Dagger, for builds and CI
                """).font(.caption)
                link("Full third-party notices", "https://github.com/\(AppIdentity.repository)/blob/main/THIRD_PARTY_NOTICES.md")

                HStack { Spacer(); Button("Close") { isPresented = false } }
            }.padding()
        }
        .frame(minWidth: 540, minHeight: 460)
    }
}
