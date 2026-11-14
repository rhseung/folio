import FolioDomain
import Foundation
import Synchronization

#if os(macOS)
// Claude Code의 자체 도구는 꺼서 Claude가 파일을 건드리지 못하게 한다. `folio mcp --propose`는 자유롭게 읽지만, 모든
// 변경을 사용자가 패널에서 승인하는 제안으로 바꾼다.
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

    // Finder에서 연 앱은 셸의 PATH를 받지 못하므로, 흔히 설치되는 위치를 직접 확인한다.
    public static func find() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    public static func findFolio() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/folio", "/opt/homebrew/bin/folio", "/usr/local/bin/folio"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func arguments(for request: MessagesRequest, systemFile: URL?, folio: FolioTools? = nil) throws -> [String] {
        var args = [
            "-p", "--verbose", "--input-format", "stream-json", "--output-format", "stream-json",
            "--model", request.model, "--tools", "", "--setting-sources", "", "--strict-mcp-config",
            "--disable-slash-commands", "--no-session-persistence",
        ]
        if let folio {
            let server: [String: Any] = ["command": folio.executable.path, "args": ["mcp", "--gist", folio.gist.path, "--propose"]]
            let config = try JSONSerialization.data(
                withJSONObject: ["mcpServers": ["folio": server]], options: [.sortedKeys, .withoutEscapingSlashes])
            args += ["--mcp-config", String(decoding: config, as: UTF8.self), "--allowedTools", "mcp__folio"]
        }
        if let systemFile { args += ["--system-prompt-file", systemFile.path] }
        if let effort = request.output_config?.effort { args += ["--effort", effort.rawValue] }
        if let schema = request.output_config?.format?.schema {
            args += ["--json-schema", String(decoding: try JSONEncoder().encode(schema), as: UTF8.self)]
        }
        return args
    }

    // CLI는 assistant 차례를 입력으로 받지 않으므로, 이전 차례를 대화 기록으로 만들어 앞에 붙인다.
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

    static func response(from output: Data, request: MessagesRequest) throws -> MessagesResponse {
        let lines = String(decoding: output, as: UTF8.self).split(separator: "\n")
        guard let line = lines.last(where: { $0.contains(#""type":"result""#) }),
            let result = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        else {
            throw ClaudeError.http(status: 0, body: String(lines.suffix(3).joined(separator: "\n")))
        }
        func string(_ v: JSONValue?) -> String? { if case .string(let s)? = v { s } else { nil } }
        func int(_ v: JSONValue?) -> Int { if case .number(let n)? = v { Int(n) } else { 0 } }
        if result["is_error"] == .bool(true) {
            throw ClaudeError.http(
                status: int(result["api_error_status"]), body: string(result["result"]) ?? string(result["subtype"]) ?? "")
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
        let stop = string(result["stop_reason"]).map { $0 == "tool_use" ? "end_turn" : $0 }
        let found = proposals(lines)
        return MessagesResponse(
            id: string(result["session_id"]) ?? "cli", model: model, content: [.text(text)], stop_reason: stop,
            usage: Usage(
                input_tokens: int(usage?["input_tokens"]), output_tokens: int(usage?["output_tokens"]),
                cache_creation_input_tokens: int(usage?["cache_creation_input_tokens"]),
                cache_read_input_tokens: int(usage?["cache_read_input_tokens"])),
            proposals: found.isEmpty ? nil : found
        )
    }

    static func proposals(_ lines: [Substring]) -> [ActionProposal] {
        lines.flatMap { line -> [ActionProposal] in
            guard line.contains(ActionProposal.marker), let value = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
                value["type"] == .string("user"), case .array(let blocks)? = value["message"]?["content"]
            else { return [] }
            return blocks.flatMap { block -> [ActionProposal] in
                guard block["type"] == .string("tool_result") else { return [] }
                let texts: [JSONValue] =
                    if case .array(let a)? = block["content"] { a.compactMap { $0["text"] } } else { [block["content"] ?? .null] }
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

    static func event(_ line: Data) -> StreamEvent? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: line), value["type"] == .string("stream_event"),
            let event = value["event"]
        else { return nil }
        switch event["type"] {
        case .string("message_start"):
            return .turn
        case .string("content_block_start"):
            guard let block = event["content_block"], block["type"] == .string("tool_use"), case .string(let name)? = block["name"] else {
                return nil
            }
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

        // 과목 맥락은 수백 KB에 이르러 인자 크기 한도를 넘을 수 있으므로 파일로 넘긴다.
        var systemFile: URL?
        if let system = Self.systemText(request) {
            systemFile = temp.appending(path: "system.txt")
            try system.write(to: systemFile!, atomically: true, encoding: .utf8)
        }

        let args =
            try Self.arguments(for: request, systemFile: systemFile, folio: folio) + (onEvent == nil ? [] : ["--include-partial-messages"])
        let (executable, cwd, errorFile) = (executable, workingDirectory, temp.appending(path: "stderr.txt"))
        let running = Running()
        // 읽기가 스레드를 막으므로 detached task에서 돌린다. detached task는 취소를 물려받지 않으므로, 핸들러가
        // 프로세스를 끝내서 읽기도 함께 끝낸다.
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

    static func run(
        _ executable: URL, _ args: [String], input: Data, cwd: URL?, stderr: URL, running: Running = Running(),
        onLine: (Data) -> Void = { _ in }
    ) throws -> (Data, Int32) {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }

        let stdin = Pipe(), stdout = Pipe()
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        process.standardInput = stdin
        process.standardOutput = stdout
        // pipe가 아니라 파일에 쓴다. 아무도 읽지 않는 stderr pipe가 가득 차면 프로세스가 멈추기 때문이다.
        process.standardError = try FileHandle(forWritingTo: stderr)

        try running.start(process)
        let writer = stdin.fileHandleForWriting
        // 입력을 다 읽기 전에 멈춘 프로세스에 아래에서 쓰면 SIGPIPE로 앱이 종료되므로 이를 막는다.
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        Thread.detachNewThread {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }

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

    // 요청마다 프로세스를 두어야 요청을 취소할 때 프로세스도 끝난다. 그러지 않으면 아무도 보지 않을 답을 `claude`가
    // 끝까지 쓰고, 그만큼 요금이 나간다.
    final class Running: Sendable {
        private let state = Mutex<(process: Process?, cancelled: Bool)>((nil, false))

        // 프로세스가 시작되는 사이에 들어온 취소를 놓치지 않도록 잠금 안에서 시작한다. 시작하지 않은 프로세스에
        // `terminate()`를 부르면 Objective-C 예외가 나기 때문이기도 하다.
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
