// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// openmila-mcp - the MCP stdio server over OpenMila's transcriptions. The port
// twin of upstream's MilaMCP/MilaMCPMain.swift; see CHANGES.md.
//
// Upstream drives the protocol with the MCP Swift SDK. The port speaks it
// directly, for one reason: the SDK's HTTP transport imports EventSource under
// `#if !os(Linux)`, but the package links it on Apple platforms only, so the
// module is missing exactly on Windows ("no such module 'EventSource'"). The
// SDK also pulls in swift-nio for transports this helper never uses. MCP over
// stdio is newline-delimited JSON-RPC 2.0, which is small enough to own.
//
// All tool logic still lives in MilaKit's `MilaMCPToolHandlers` (pure
// JSON-in/JSON-out), exactly as upstream: this file is only the transport.

import Foundation
import MilaKit

@main
struct OpenMilaMCPMain {
    /// The newest protocol revision this helper implements. A client that asks
    /// for a different one is answered with its own, as the specification
    /// requires, as long as we can serve it: tools over stdio have not changed
    /// across these revisions.
    static let protocolVersion = "2025-06-18"

    static func main() async throws {
        let handlers = MilaMCPToolHandlers(root: storeRoot())
        let output = FileHandle.standardOutput

        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                write(errorResponse(id: nil, code: -32700, message: "Parse error"), to: output)
                continue
            }
            // A notification has no id and takes no reply, ever.
            let id = message["id"]
            guard let method = message["method"] as? String else { continue }
            guard let reply = respond(to: method, params: message["params"] as? [String: Any],
                                      id: id, handlers: handlers) else { continue }
            write(reply, to: output)
        }
    }

    private static func respond(to method: String, params: [String: Any]?, id: Any?,
                                handlers: MilaMCPToolHandlers) -> [String: Any]? {
        guard let id else { return nil }   // notification
        switch method {
        case "initialize":
            let requested = (params?["protocolVersion"] as? String) ?? protocolVersion
            return success(id: id, result: [
                "protocolVersion": requested,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "openmila", "version": appVersion()],
            ])
        case "ping":
            return success(id: id, result: [:])
        case "tools/list":
            let tools = MilaMCPToolHandlers.toolSpecs.map { spec in
                ["name": spec.name, "description": spec.description, "inputSchema": spec.inputSchema]
            }
            return success(id: id, result: ["tools": tools])
        case "tools/call":
            let name = (params?["name"] as? String) ?? ""
            let arguments = (params?["arguments"] as? [String: Any]) ?? [:]
            do {
                let text = try handlers.handle(tool: name, arguments: arguments)
                return success(id: id, result: ["content": [["type": "text", "text": text]],
                                                "isError": false])
            } catch {
                // A refused or failed tool call is a RESULT with isError, not a
                // protocol error: the client shows the text to the model, which
                // is how the consent gate explains itself.
                return success(id: id, result: ["content": [["type": "text", "text": String(describing: error)]],
                                                "isError": true])
            }
        default:
            return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private static func success(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        var response: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        response["id"] = id ?? NSNull()
        return response
    }

    private static func write(_ message: [String: Any], to output: FileHandle) {
        guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]) else { return }
        data.append(0x0A)   // one message per line, as MCP's stdio transport requires
        output.write(data)
    }

    /// The app-support root every cross-process contract is resolved from.
    /// Upstream's reasoning for keeping the environment override out of
    /// release builds applies unchanged: the consent file, the store pointer
    /// and the live sidecar all hang off this root, so a client that could
    /// set it could grant itself access to the real store.
    private static func storeRoot() -> URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["MILA_ROOT"] {
            FileHandle.standardError.write(Data("openmila-mcp: DEBUG build honouring MILA_ROOT=\(override)\n".utf8))
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        return StoreLocationPointer.defaultRoot()
    }

    /// Reported in the initialize handshake so a bug report names the build.
    private static func appVersion() -> String {
        ProcessInfo.processInfo.environment["OPENMILA_VERSION"] ?? "dev"
    }
}
