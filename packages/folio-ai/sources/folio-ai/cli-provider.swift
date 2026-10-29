import FolioDomain
import Foundation

#if os(macOS)
/// Runs the user's own Claude Code CLI on their subscription (docs/SPEC.md "호출 방식"). Every tool is off, so Claude
/// only answers: it cannot read or change the GIST folder, and results stay proposals.
public struct CLIProvider: ClaudeProvider {
    let executable: URL
    let workingDirectory: URL?

    public init(executable: URL, workingDirectory: URL? = nil) {
        self.executable = executable
        self.workingDirectory = workingDirectory
    }

    /// Apps opened from the Finder don't get the shell's PATH, so the usual install places are checked directly.
    public static func find() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func arguments(for request: MessagesRequest, systemFile: URL?) throws -> [String] {
        var args = ["-p", "--verbose", "--input-format", "stream-json", "--output-format", "stream-json",
                    "--model", request.model, "--tools", "", "--setting-sources", "", "--strict-mcp-config",
                    "--disable-slash-commands", "--no-session-persistence"]
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
        return MessagesResponse(
            id: string(result["session_id"]) ?? "cli", model: model, content: [.text(text)], stop_reason: stop,
            usage: Usage(input_tokens: int(usage?["input_tokens"]), output_tokens: int(usage?["output_tokens"]),
                         cache_creation_input_tokens: int(usage?["cache_creation_input_tokens"]),
                         cache_read_input_tokens: int(usage?["cache_read_input_tokens"]))
        )
    }

    public func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        try await respond(request, onText: nil)
    }

    public func send(_ request: MessagesRequest, onText: @escaping @Sendable (String) -> Void) async throws -> MessagesResponse {
        try await respond(request, onText: onText)
    }

    /// The text a `--include-partial-messages` stream line adds to the answer, if it is a text delta.
    static func textDelta(_ line: Data) -> String? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: line), value["type"] == .string("stream_event"),
              let event = value["event"], event["type"] == .string("content_block_delta"),
              let delta = event["delta"], delta["type"] == .string("text_delta"), case .string(let text)? = delta["text"] else { return nil }
        return text
    }

    func respond(_ request: MessagesRequest, onText: (@Sendable (String) -> Void)?) async throws -> MessagesResponse {
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
        let args = try Self.arguments(for: request, systemFile: systemFile) + (onText == nil ? [] : ["--include-partial-messages"])
        let (executable, cwd, errorFile) = (executable, workingDirectory, temp.appending(path: "stderr.txt"))
        // shortcut: a cancelled task lets the process run to the end; terminate it once long requests can be cancelled.
        let (output, status) = try await Task.detached {
            try Self.run(executable, args, input: input, cwd: cwd, stderr: errorFile) { line in
                if let onText, let text = Self.textDelta(line) { onText(text) }
            }
        }.value
        do {
            return try Self.response(from: output, request: request)
        } catch ClaudeError.http(status: 0, _) where status != 0 {
            let message = (try? String(contentsOf: errorFile, encoding: .utf8)) ?? ""
            throw ClaudeError.http(status: Int(status), body: message.isEmpty ? "claude exited with \(status)" : message)
        }
    }

    static func run(_ executable: URL, _ args: [String], input: Data, cwd: URL?, stderr: URL,
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
        try process.run()
        let writer = stdin.fileHandleForWriting
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
}
#endif
