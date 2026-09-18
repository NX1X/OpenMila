// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Upstream declares this protocol inside `DiagnosticReporter.swift`, which is
// AppKit-bound and excluded from the port. Portable settings objects conform
// to it, so the declaration is repeated here until the port's own diagnostic
// reporter lands and takes ownership of it.

protocol DiagnosticSnapshotProvider: Sendable {
    func diagnosticSnapshot() async -> String
}
