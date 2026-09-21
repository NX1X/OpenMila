// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import XCTest
@testable import OpenMilaLogging

/// The log lines carry the port's identity, not Mila's, without any upstream
/// file being edited: the shim remaps the subsystem at construction.
final class LoggerSubsystemTests: XCTestCase {
    func test_upstreams_main_subsystems_become_the_ports_own() {
        XCTAssertEqual(Logger.portSubsystem(for: "io.island.whisper.IslandWhisper"), "io.github.nx1x.openmila")
        XCTAssertEqual(Logger.portSubsystem(for: "io.island.mila.Mila"), "io.github.nx1x.openmila")
        XCTAssertEqual(Logger.portSubsystem(for: "io.island.Island"), "io.github.nx1x.openmila")
    }

    /// A specific tail is kept, so a line still says which part of the code
    /// wrote it.
    func test_a_specific_tail_is_kept_under_the_ports_name() {
        XCTAssertEqual(Logger.portSubsystem(for: "io.island.mila.claude"), "io.github.nx1x.openmila.mila.claude")
        XCTAssertEqual(Logger.portSubsystem(for: "io.island.mila.updates"), "io.github.nx1x.openmila.mila.updates")
    }

    func test_the_ports_own_subsystems_pass_through() {
        XCTAssertEqual(Logger.portSubsystem(for: "io.github.nx1x.openmila"), "io.github.nx1x.openmila")
        XCTAssertEqual(Logger.portSubsystem(for: "openmila"), "openmila")
    }
}
