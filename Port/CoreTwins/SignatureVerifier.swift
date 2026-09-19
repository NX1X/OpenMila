// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Off-macOS stand-in for upstream's `SecurityFrameworkSignatureVerifier`
// (Apple code signing, guarded behind `canImport(Security)` upstream-side).
//
// It FAILS CLOSED. Upstream's install flow accepts a downloaded Claude binary
// only when a verifier reports a valid signature from Anthropic's Apple team
// id. Linux and Windows builds of that binary carry no Apple signature, so the
// honest answer here is "not verified", which makes the managed install refuse
// to run the download. The published SHA-256 check still runs before this
// point. A real per-OS trust check (Authenticode on Windows, a pinned release
// signature on Linux) replaces this type in the platform layer; until then the
// feature stays off rather than running an unverified executable.

#if !canImport(Security)
import Foundation

struct SecurityFrameworkSignatureVerifier: ClaudeSignatureVerifying {
    func identity(ofBinaryAt url: URL) throws -> ClaudeSignatureIdentity {
        ClaudeSignatureIdentity(teamIdentifier: nil, signingIdentifier: nil, isValid: false)
    }
}
#endif
