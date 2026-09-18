// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import Foundation

/// Mirrors the part of `OSAllocatedUnfairLock` upstream uses: a lock that owns
/// its state and hands it to a closure. Backed by `NSLock`, which is available
/// on every platform Foundation runs on.
public final class OSAllocatedUnfairLock<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    public init(initialState: State) {
        state = initialState
    }

    public init(uncheckedState initialState: State) {
        state = initialState
    }

    @discardableResult
    public func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }

    @discardableResult
    public func withLockUnchecked<R>(_ body: (inout State) throws -> R) rethrows -> R {
        try withLock(body)
    }
}

extension OSAllocatedUnfairLock where State == Void {
    public convenience init() {
        self.init(initialState: ())
    }

    public func withLock<R>(_ body: () throws -> R) rethrows -> R {
        try withLock { (_: inout Void) in try body() }
    }
}
