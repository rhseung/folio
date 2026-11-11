import FolioDomain
import Foundation
import Synchronization

#if os(macOS)
/// Runs the user's own Claude Code CLI on their subscription. Its own tools stay off, so
/// Claude can't touch files; with `folio` given, the chat gets Folio's actions through `folio mcp --propose`, which
/// reads freely but turns every change into a proposal the user approves in the panel.
public struct CLIProvider: ClaudeProvider {
    public struct FolioTools: Sendable, Equatable {
        public var executable: URL
        public var gist: URL
        public init(executable: URL, gist: URL) {
            self.executable = executable
            self.gist = gist
        }
    }

    let executable: URL
    let workingDirectory: URL?
    let folio: FolioTools?

    public init(executable: URL, workingDirectory: URL? = nil, folio: FolioTools? = nil) {
        self.executable = executable
        self.workingDirectory = workingDirectory
        self.folio = folio
    }

    /// Apps opened from the Finder don't get the shell's PATH, so the usual install places are checked directly.
    public static func find() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Where `mise run install-cli` puts it, or Homebrew's places.
    public static func findFolio() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/folio", "/opt/homebrew/bin/folio", "/usr/local/bin/folio"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func arguments(for request: MessagesRequest, systemFile: URL?, folio: FolioTools? = nil) throws -> [String] {
        var args = ["-p", "--verbose", "--input-format", "stream-json", "--output-format", "stream-json",
                    "--model", request.model, "--tools", "", "--setting-sources", "", "--strict-mcp-config",
                    "--disable-slash-commands", "--no-session-persistence"]
        if let folio {
            let server: [String: Any] = ["command": folio.executable.path, "args": ["mcp", "--gist", folio.gist.path, "--propose"]]
            let config = try JSONSerialization.data(withJSONObject: ["mcpServers": ["folio": server]], options: [.sortedKeys, .withoutEscapingSlashes])
            // `--strict-mcp-config` above keeps the user's own servers out; only this one is allowed.
            args += ["--mcp-config", String(decoding: config, as: UTF8.self), "--allowedTools", "mcp__folio"]
        }
        if let systemFile { args += ["--system-prompt-file", systemFile.path] }
        if let effort = request.output_config?.effort { args += ["--effort", effort.rawValue] }
        if let schema = request.output_config?.format?.schema {
            args += ["--json-schema", String(decoding: try JSONEncoder().encode(schema), as: UTF8.self)]
        }
        return args
    }

    /// One user message. The CLI takes no assistant turns as input, so earlier turns go in front as a transcript.
    static func input(for request: MessagesRequest) throws -> Data {
        guard let last = request.messages.last else { throw ClaudeError.invalidOutput("no message to send") }
        let history = request.messages.dropLast().map { m in
            (m.role == .user ? "사용자: " : "Claude: ") + m.content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined()
        }
        var content = last.content
        if !history.isEmpty { content.insert(.text("지금까지의 대화:\n\n" + history.joined(separator: "\n\n")), at: 0) }
        struct Line: Encodable { var type = "user"; var message: Message }
        return try JSONEncoder().encode(Line(message: Message(role: .user, content: content))) + Data("\n".utf8)
    }

    static func systemText(_ request: MessagesRequest) -> String? {
        let text = (request.system ?? []).compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    /// The `result` line of the stream, shaped like an API response so `ClaudeClient` treats both providers alike.
    static func response(from output: Data, request: MessagesRequest) throws -> MessagesResponse {
        let lines = String(decoding: output, as: UTF8.self).split(separator: "\n")
        guard let line = lines.last(where: { $0.contains(#""type":"result""#) }),
              let result = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            throw ClaudeError.http(status: 0, body: String(lines.suffix(3).joined(separator: "\n")))
        }
        func string(_ v: JSONValue?) -> String? { if case .string(let s)? = v { s } else { nil } }
        func int(_ v: JSONValue?) -> Int { if case .number(let n)? = v { Int(n) } else { 0 } }
        if result["is_error"] == .bool(true) {
            throw ClaudeError.http(status: int(result["api_error_status"]), body: string(result["result"]) ?? string(result["subtype"]) ?? "")
        }
        let text: String
        if let structured = result["structured_output"], structured != .null {
            text = String(decoding: try JSONEncoder().encode(structured), as: UTF8.self)
        } else {
            text = string(result["result"]) ?? ""
        }
        let usage = result["usage"]
        var model = request.model
        if case .object(let models)? = result["modelUsage"], let first = models.keys.sorted().first { model = first }
        // Structured output arrives through a tool call, which is a finished answer here.
        let stop = string(result["stop_reason"]).map { $0 == "tool_use" ? "end_turn" : $0 }
        let found = proposals(lines)
        return MessagesResponse(
            id: string(result["session_id"]) ?? "cli", model: model, content: [.text(text)], stop_reason: stop,
            usage: Usage(input_tokens: int(usage?["input_tokens"]), output_tokens: int(usage?["output_tokens"]),
                         cache_creation_input_tokens: int(usage?["cache_creation_input_tokens"]),
                         cache_read_input_tokens: int(usage?["cache_read_input_tokens"])),
            proposals: found.isEmpty ? nil : found
        )
    }

    /// The changes `folio mcp --propose` handed back in tool results along the way.
    static func proposals(_ lines: [Substring]) -> [ActionProposal] {
        lines.flatMap { line -> [ActionProposal] in
            guard line.contains(ActionProposal.marker), let value = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
                  value["type"] == .string("user"), case .array(let blocks)? = value["message"]?["content"] else { return [] }
            return blocks.flatMap { block -> [ActionProposal] in
                guard block["type"] == .string("tool_result") else { return [] }
                let texts: [JSONValue] = if case .array(let a)? = block["content"] { a.compactMap { $0["text"] } } else { [block["content"] ?? .null] }
                return texts.compactMap { if case .string(let t) = $0 { ActionProposal(text: t) } else { nil } }
            }
        }
    }

    public func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        try await respond(request, onEvent: nil)
    }

    public func send(_ request: MessagesRequest, onEvent: @escaping @Sendable (StreamEvent) -> Void) async throws -> MessagesResponse {
        try await respond(request, onEvent: onEvent)
    }

    /// A line of `--include-partial-messages` output. Each assistant message, one per tool round, opens with
    /// `message_start`; a tool call opens its block with the tool's name before its input streams in.
    static func event(_ line: Data) -> StreamEvent? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: line), value["type"] == .string("stream_event"),
              let event = value["event"] else { return nil }
        switch event["type"] {
        case .string("message_start"):
            return .turn
        case .string("content_block_start"):
            guard let block = event["content_block"], block["type"] == .string("tool_use"), case .string(let name)? = block["name"] else { return nil }
            return .tool(name)
        case .string("content_block_delta"):
            guard let delta = event["delta"] else { return nil }
            if delta["type"] == .string("input_json_delta"), case .string(let json)? = delta["partial_json"] { return .toolInput(json) }
            guard delta["type"] == .string("text_delta"), case .string(let text)? = delta["text"] else { return nil }
            return .text(text)
        default:
            return nil
        }
    }

    func respond(_ request: MessagesRequest, onEvent: (@Sendable (StreamEvent) -> Void)?) async throws -> MessagesResponse {
        let input = try Self.input(for: request)
        let temp = FileManager.default.temporaryDirectory.appending(path: "folio-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        // The course context can run to hundreds of kilobytes, past the argument size limit, so it goes in a file.
        var systemFile: URL?
        if let system = Self.systemText(request) {
            systemFile = temp.appending(path: "system.txt")
            try system.write(to: systemFile!, atomically: true, encoding: .utf8)
        }
        let args = try Self.arguments(for: request, systemFile: systemFile, folio: folio) + (onEvent == nil ? [] : ["--include-partial-messages"])
        let (executable, cwd, errorFile) = (executable, workingDirectory, temp.appending(path: "stderr.txt"))
        let running = Running()
        // Detached because the read blocks its thread. A detached task doesn't inherit cancellation, so the handler
        // carries it over by ending the process, which ends the read too.
        let (output, status) = try await withTaskCancellationHandler {
            try await Task.detached {
                try Self.run(executable, args, input: input, cwd: cwd, stderr: errorFile, running: running) { line in
                    if let onEvent, let event = Self.event(line) { onEvent(event) }
                }
            }.value
        } onCancel: {
            running.cancel()
        }
        try Task.checkCancellation()
        do {
            return try Self.response(from: output, request: request)
        } catch ClaudeError.http(status: 0, _) where status != 0 {
            let message = (try? String(contentsOf: errorFile, encoding: .utf8)) ?? ""
            throw ClaudeError.http(status: Int(status), body: message.isEmpty ? "claude exited with \(status)" : message)
        }
    }

    static func run(_ executable: URL, _ args: [String], input: Data, cwd: URL?, stderr: URL, running: Running = Running(),
                    onLine: (Data) -> Void = { _ in }) throws -> (Data, Int32) {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }
        let stdin = Pipe(), stdout = Pipe()
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        process.standardInput = stdin
        process.standardOutput = stdout
        // A file, not a pipe: an unread stderr pipe that fills up would stall the process.
        process.standardError = try FileHandle(forWritingTo: stderr)
        try running.start(process)
        let writer = stdin.fileHandleForWriting
        // A process stopped before it read all its input would otherwise kill the app with SIGPIPE on the write below.
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        // Written from another thread so a long prompt can't block while stdout fills.
        Thread.detachNewThread {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }
        // Read as it comes, not to the end, so the answer's text deltas reach the panel while it is being written.
        let reader = stdout.fileHandleForReading
        var output = Data(), pending = Data()
        while case let chunk = reader.availableData, !chunk.isEmpty {
            output.append(chunk)
            pending.append(chunk)
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                onLine(pending[pending.startIndex..<newline])
                pending = Data(pending[pending.index(after: newline)...])
            }
        }
        process.waitUntilExit()
        return (output, process.terminationStatus)
    }

    /// One request's process, so cancelling the request ends it. Otherwise `claude` runs on, and bills, to the end of
    /// an answer nobody will see.
    final class Running: Sendable {
        private let state = Mutex<(process: Process?, cancelled: Bool)>((nil, false))

        /// Under the lock, so a cancel that lands while the process starts isn't lost; and `terminate()` on a process
        /// not yet started raises an Objective-C exception rather than doing nothing.
        func start(_ process: Process) throws {
            try state.withLock { s in
                if s.cancelled { throw CancellationError() }
                try process.run()
                s.process = process
            }
        }

        func cancel() {
            state.withLock { s in
                s.cancelled = true
                s.process?.terminate()
            }
        }
    }
}
#endif
