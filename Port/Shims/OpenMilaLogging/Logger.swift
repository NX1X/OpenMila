// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

import Foundation
import Logging

/// Privacy of one interpolated value, mirroring `OSLogPrivacy`.
///
/// Upstream's rule (bugbot-rules/no-user-content-in-logs.md) is that user
/// content never reaches a public log field. This shim keeps that split:
/// `.private` values are replaced by `<private>` unless private logging is
/// switched on for a debugging session.
public struct OSLogPrivacy: Sendable, Equatable {
    enum Kind: Sendable { case auto, `public`, `private`, sensitive }
    let kind: Kind

    public static let auto = OSLogPrivacy(kind: .auto)
    public static let `public` = OSLogPrivacy(kind: .public)
    public static let `private` = OSLogPrivacy(kind: .private)
    public static let sensitive = OSLogPrivacy(kind: .sensitive)
}

/// Process-wide switch for revealing `.private` values. Off by default and
/// only settable through the environment, so a shipped build cannot be asked
/// to reveal user content by a config file or a remote setting.
public enum OpenMilaLogPrivacy {
    public static let revealPrivate: Bool =
        ProcessInfo.processInfo.environment["OPENMILA_LOG_PRIVATE"] == "1"
}

/// The message type the `Logger` methods take, mirroring `OSLogMessage`.
/// A string literal with interpolations builds one of these, which is how
/// `\(value, privacy: .public)` compiles unchanged.
public struct OSLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral, Sendable {
    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        var rendered = ""

        public init(literalCapacity: Int, interpolationCount: Int) {
            rendered.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: String) {
            rendered += literal
        }

        /// `os.Logger` treats a bare dynamic string as private and a bare
        /// number as public. `.auto` reproduces that.
        public mutating func appendInterpolation<T>(
            _ value: @autoclosure () -> T,
            privacy: OSLogPrivacy = .auto
        ) {
            let isPublic: Bool
            switch privacy.kind {
            case .public: isPublic = true
            case .private, .sensitive: isPublic = false
            case .auto: isPublic = !(T.self == String.self || T.self == Substring.self)
            }
            if isPublic || OpenMilaLogPrivacy.revealPrivate {
                rendered += String(describing: value())
            } else {
                rendered += "<private>"
            }
        }
    }

    let text: String

    public init(stringInterpolation: StringInterpolation) { text = stringInterpolation.rendered }
    public init(stringLiteral value: String) { text = value }
}

/// Mirrors `os.Logger` over swift-log.
public struct Logger: Sendable {
    private let backing: Logging.Logger

    public init(subsystem: String, category: String) {
        var logger = Logging.Logger(label: Self.portSubsystem(for: subsystem))
        logger[metadataKey: "category"] = .string(category)
        backing = logger
    }

    /// Upstream names its log subsystems after itself: `io.island.whisper.
    /// IslandWhisper`, `io.island.mila.Mila`, and a handful more, in about
    /// seventy files. Those are Mila's identifiers, not this port's, and they
    /// are what a user reads in every line of openmila.log. Rather than edit
    /// every upstream file (and merge every one on each sync), the shim maps
    /// them here: the `io.island.` prefix becomes the port's own reverse-DNS
    /// name, and whatever followed it is kept, so `io.island.mila.claude`
    /// reads `io.github.nx1x.openmila.mila.claude` and a line is still
    /// traceable to the code that wrote it. Only logging is touched; the
    /// UserDefaults suites and queue labels that share those strings are
    /// persistence contracts and stay exactly as upstream wrote them.
    static func portSubsystem(for upstream: String) -> String {
        let prefix = "io.island."
        guard upstream.hasPrefix(prefix) else { return upstream }
        let rest = upstream.dropFirst(prefix.count)
        // The two most common tails say nothing a reader needs.
        switch rest {
        case "whisper.IslandWhisper", "mila.Mila", "Island":
            return "io.github.nx1x.openmila"
        default:
            return "io.github.nx1x.openmila." + rest
        }
    }

    public init() {
        backing = Logging.Logger(label: "openmila")
    }

    public func log(_ message: OSLogMessage) { backing.notice("\(message.text)") }
    public func trace(_ message: OSLogMessage) { backing.trace("\(message.text)") }
    public func debug(_ message: OSLogMessage) { backing.debug("\(message.text)") }
    public func info(_ message: OSLogMessage) { backing.info("\(message.text)") }
    public func notice(_ message: OSLogMessage) { backing.notice("\(message.text)") }
    public func warning(_ message: OSLogMessage) { backing.warning("\(message.text)") }
    public func error(_ message: OSLogMessage) { backing.error("\(message.text)") }
    public func critical(_ message: OSLogMessage) { backing.critical("\(message.text)") }
    public func fault(_ message: OSLogMessage) { backing.critical("\(message.text)") }
}
