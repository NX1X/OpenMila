// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Bridges upstream's Combine `ObservableObject`s (OpenCombine off macOS) into
// SwiftCrossUI's observation system, so a view can hold a core object with
// `@State var store = Observed(core.store)` and re-render on its changes.

import Combine
import Foundation
import SwiftCrossUI

@MainActor
public final class Observed<Object: Combine.ObservableObject>: SwiftCrossUI.ObservableObject {
    public let object: Object
    public let didChange = Publisher()
    private var subscription: AnyCancellable?

    public init(_ object: Object) {
        self.object = object
        // `objectWillChange` fires before the mutation; deliver after it lands.
        subscription = object.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.didChange.send() }
        }
    }
}

/// Hebrew is written right to left. Upstream decides direction per text block
/// by counting Hebrew versus Latin letters (`HebrewDetection`).
extension String {
    var isRTLText: Bool {
        var hebrew = 0, latin = 0
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x0590...0x05FF: hebrew += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        return hebrew > latin
    }
}
