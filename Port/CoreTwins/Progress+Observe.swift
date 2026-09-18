// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Key-value observing is an Objective-C runtime feature and does not exist off
// Apple platforms. Upstream observes one thing with it, in one place: a
// download task's `Progress.fractionCompleted`, to drive a progress bar.
//
// This provides the same call shape for `Progress` by sampling the value on a
// timer and reporting changes. It is deliberately limited to `Progress`; it is
// not a general KVO replacement.

#if !canImport(ObjectiveC)
import Foundation

public struct NSKeyValueObservingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let new = NSKeyValueObservingOptions(rawValue: 1 << 0)
    public static let old = NSKeyValueObservingOptions(rawValue: 1 << 1)
    public static let initial = NSKeyValueObservingOptions(rawValue: 1 << 2)
}

public struct NSKeyValueObservedChange<Value> {
    public let newValue: Value?
    public let oldValue: Value?
}

/// Token that keeps an observation alive. Releasing or invalidating it stops
/// the sampling timer, matching how upstream holds the real thing.
public final class NSKeyValueObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?

    init(timer: DispatchSourceTimer) { self.timer = timer }

    public func invalidate() {
        lock.lock()
        let active = timer
        timer = nil
        lock.unlock()
        active?.cancel()
    }

    deinit { invalidate() }
}

extension Progress {
    /// Samples `keyPath` ten times a second and calls `changeHandler` when the
    /// value changes. Stops by itself once the progress reports finished.
    public func observe<Value: Equatable>(
        _ keyPath: KeyPath<Progress, Value>,
        options: NSKeyValueObservingOptions = [],
        changeHandler: @escaping (Progress, NSKeyValueObservedChange<Value>) -> Void
    ) -> NSKeyValueObservation {
        let queue = DispatchQueue(label: "io.github.nx1x.openmila.progress-observe")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        var last = self[keyPath: keyPath]
        if options.contains(.initial) {
            changeHandler(self, NSKeyValueObservedChange(newValue: last, oldValue: nil))
        }
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        // The handler must not keep the timer alive through itself, so it reaches
        // it through the observation token, held weakly.
        let token = NSKeyValueObservation(timer: timer)
        timer.setEventHandler { [weak self, weak token] in
            guard let self else { token?.invalidate(); return }
            let current = self[keyPath: keyPath]
            if current != last {
                let previous = last
                last = current
                changeHandler(self, NSKeyValueObservedChange(newValue: current, oldValue: previous))
            }
            if self.isFinished { token?.invalidate() }
        }
        timer.resume()
        return token
    }
}
#endif
