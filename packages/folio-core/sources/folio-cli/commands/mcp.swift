import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

/// `folio mcp`: the same actions and read commands as MCP tools over standard input and output (docs/SPEC.md
/// "에이전트용 호출"). The client starts it per session, so there is no server to keep running.
struct MCPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp", abstract: String(localized: .mcpAbstract), discussion: String(localized: .mcpDiscussion))

    @Option(help: ArgumentHelp(String(localized: .globalOptionsHelpGist), valueName: "path")) var gist: String?
    @Flag(help: ArgumentHelp(String(localized: .mcpHelpPropose))) var propose = false

    func run() throws {
        let server = MCPServer(gist: gist, propose: propose)
        // stdout carries the protocol, so replies are written straight to it and never through `print`'s buffer.
        while let line = readLine() {
            guard let reply = server.handle(line) else { continue }
            FileHandle.standardOutput.write(reply + Data("\n".utf8))
        }
    }
}

struct MCPServer {
    static let versions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    struct Tool {
        var name: String
        var command: String
        var write: Bool
        var spec: JSONValue
        var argv: (JSONValue) -> [String]
    }

    let gist: String?
    let propose: Bool
    let tools: [Tool]

    init(gist: String?, propose: Bool) {
        self.gist = gist
        self.propose = propose
        tools = Self.writeTools(propose: propose) + Self.readTools()
    }

    /// One JSON-RPC line in, the reply line out; notifications get none.
    func handle(_ line: String) -> Data? {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            return Self.encode(["jsonrpc": "2.0", "id": .null, "error": ["code": .number(-32700), "message": "parse error"]])
        }
        guard let id = message["id"], case .string(let method)? = message["method"] else { return nil }
        let params = message["params"] ?? [:]
        let result: JSONValue
        switch method {
        case "initialize":
            let asked = params["protocolVersion"].flatMap { if case .string(let v) = $0 { v } else { nil } }
            var text = actionRefNote
            if propose { text += "\n\n" + String(localized: .mcpInstructionsPropose) }
            result = [
                "protocolVersion": .string(asked.flatMap { Self.versions.contains($0) ? $0 : nil } ?? Self.versions[0]),
                "capabilities": ["tools": ["listChanged": .bool(false)]],
                "serverInfo": ["name": "folio", "version": "1"],
                "instructions": .string(text),
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": .array(tools.map(\.spec))]
        case "tools/call":
            guard case .string(let name)? = params["name"], let tool = tools.first(where: { $0.name == name }) else {
                return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": .number(-32602), "message": "unknown tool"]])
            }
            result = call(tool, params["arguments"] ?? [:])
        default:
            return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": .number(-32601), "message": .string("unknown method: \(method)")]])
        }
        return Self.encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    func call(_ tool: Tool, _ arguments: JSONValue) -> JSONValue {
        var argv = tool.argv(arguments)
        var options = gist.map { ["--gist", $0] } ?? []
        if tool.write, propose || arguments["dryRun"] == .bool(true) { options.append("--dry-run") }
        argv.insert(contentsOf: options, at: argv.firstIndex(of: "--") ?? argv.endIndex)
        let out = Output()
        let built = Output()
        let code = Built.$record.withValue({ command, input in built.add(command, input) }) {
            Sink.$current.withValue(Sink(out: { out.add("out", .string($0)) }, err: { out.add("err", .string($0)) })) {
                Folio.run(argv)
            }
        }
        let text = (code == 0 ? out.lines("out") : out.lines("err") + out.lines("out")).joined(separator: "\n")
        var content: [JSONValue] = [["type": "text", "text": .string(text)]]
        // What the panel shows an approve button for: the action with every name already resolved to its UUID.
        if code == 0, tool.write, propose, let input = built.items.first(where: { $0.0 == tool.command })?.1 {
            // In the result too: the app replaces the system prompt, so the server's instructions may never reach Claude.
            content.insert(["type": "text", "text": .string(String(localized: .mcpInstructionsPropose))], at: 0)
            content.append(["type": "text", "text": .string(ActionProposal(command: tool.command, input: input).text)])
        }
        return ["content": .array(content), "isError": .bool(code != 0)]
    }

    // MARK: Tools

    static func name(_ command: String) -> String {
        command.replacing(" --", with: "_").replacing(" ", with: "_")
    }

    static func writeTools(propose: Bool) -> [Tool] {
        guard case .object(let all) = actionSchemas(), case .array(let actions)? = all["actions"], case .object(let defs)? = all["$defs"] else { return [] }
        return actions.compactMap { a -> Tool? in
            guard case .string(let command)? = a["command"], var input = a["input"] else { return nil }
            if !propose { input["properties"]?["dryRun"] = ["type": "boolean", "description": .string(String(localized: .mcpDryRunHelp))] }
            let used = referenced(input, defs)
            if !used.isEmpty { input["$defs"] = .object(defs.filter { used.contains($0.key) }) }
            let removes = a["asks"] == .bool(true)
            let summary = a["summary"].flatMap { if case .string(let s) = $0 { s } else { nil } } ?? command
            let spec: JSONValue = [
                "name": .string(name(command)),
                "title": .string(summary),
                "description": .string(summary + (removes ? " " + String(localized: .mcpRemovesNote) : "")),
                "inputSchema": input,
                "annotations": ["readOnlyHint": .bool(false), "destructiveHint": .bool(removes), "openWorldHint": .bool(false)],
            ]
            return Tool(name: name(command), command: command, write: true, spec: spec) { args in
                var input = args
                input["dryRun"] = nil
                return ["run"] + command.split(separator: " ").map(String.init) + ["--input", string(input), "--json", "--yes"]
            }
        }
    }

    /// Names of `$defs` entries the schema reaches, following entries that refer to others.
    static func referenced(_ schema: JSONValue, _ defs: [String: JSONValue]) -> Set<String> {
        var found: Set<String> = []
        func walk(_ v: JSONValue) {
            switch v {
            case .object(let o):
                if case .string(let ref)? = o["$ref"], ref.hasPrefix("#/$defs/") {
                    let key = String(ref.dropFirst("#/$defs/".count))
                    if found.insert(key).inserted, let d = defs[key] { walk(d) }
                }
                o.values.forEach(walk)
            case .array(let a): a.forEach(walk)
            default: break
            }
        }
        walk(schema)
        return found
    }

    /// Commands that only read, and are about the GIST data rather than the tool itself.
    static let notTools: Set<String> = ["actions", "run", "skill", "completion", "mcp", "unlock", "lock", "cleanup plan", "help"]
    static let globalOptions: Set<String> = ["gist", "json", "dry-run", "yes", "no-pick", "help", "version"]

    struct Help: Decodable {
        struct Command: Decodable {
            var commandName: String
            var abstract: String?
            var shouldDisplay: Bool?
            var subcommands: [Command]?
            var arguments: [Argument]?
        }
        struct Argument: Decodable {
            struct Name: Decodable { var kind: String, name: String }
            var kind: String
            var shouldDisplay: Bool
            var isOptional: Bool
            var isRepeating: Bool
            var preferredName: Name?
            var valueName: String?
            var abstract: String?
            var allValues: [String]?
        }
        var command: Command
    }

    /// Read off ArgumentParser's own description of the commands, so a new read command needs no tool code.
    static func readTools() -> [Tool] {
        let dump: String
        do {
            _ = try Folio.parseAsRoot(["--experimental-dump-help"])
            return []
        } catch {
            dump = Folio.fullMessage(for: error)
        }
        guard let help = try? JSONDecoder().decode(Help.self, from: Data(dump.utf8)) else { return [] }
        let writes = Set(Actions.all.map { $0.command })
        func leaves(_ c: Help.Command, _ path: [String]) -> [([String], Help.Command)] {
            guard let subs = c.subcommands, !subs.isEmpty else { return [(path, c)] }
            return subs.filter { $0.shouldDisplay != false }.flatMap { leaves($0, path + [$0.commandName]) }
        }
        return leaves(help.command, []).compactMap { path, c in
            let command = path.joined(separator: " ")
            guard !path.isEmpty, !writes.contains(command), !notTools.contains(command), !notTools.contains(path[0]) else { return nil }
            return readTool(command, c)
        }
    }

    static func readTool(_ command: String, _ c: Help.Command) -> Tool {
        let args = (c.arguments ?? []).filter { a in
            a.shouldDisplay && !(a.preferredName.map { globalOptions.contains($0.name) } ?? false)
        }
        func key(_ a: Help.Argument) -> String { a.kind == "positional" ? (a.valueName ?? "value") : a.preferredName?.name ?? a.valueName ?? "value" }
        var properties: [String: JSONValue] = [:]
        var required: [JSONValue] = []
        for a in args where properties[key(a)] == nil {
            var one: JSONValue = a.kind == "flag" ? ["type": "boolean"] : ["type": "string"]
            if let values = a.allValues, !values.isEmpty { one["enum"] = .array(values.map(JSONValue.string)) }
            var p = a.isRepeating && a.kind != "flag" ? ["type": "array", "items": one] : one
            if let help = a.abstract, !help.isEmpty { p["description"] = .string(help) }
            properties[key(a)] = p
            if !a.isOptional { required.append(.string(key(a))) }
        }
        let summary = c.abstract ?? command
        let spec: JSONValue = [
            "name": .string(name(command)),
            "title": .string(summary),
            "description": .string(summary),
            "inputSchema": ["type": "object", "properties": .object(properties), "required": .array(required)],
            "annotations": ["readOnlyHint": .bool(true), "openWorldHint": .bool(false)],
        ]
        return Tool(name: name(command), command: command, write: false, spec: spec) { input in
            var options: [String] = [], positionals: [String] = []
            for a in args {
                guard let v = input[key(a)], v != .null else { continue }
                let values: [String] = if case .array(let items) = v { items.map(word) } else { [word(v)] }
                switch a.kind {
                case "positional": positionals += values
                case "flag": if v == .bool(true) { options.append("--\(key(a))") }
                default: for value in values { options += ["--\(key(a))", value] }
                }
            }
            // After `--` a name like `-1` stays a value instead of reading as an option.
            return command.split(separator: " ").map(String.init) + options + ["--json"] + (positionals.isEmpty ? [] : ["--"] + positionals)
        }
    }

    static func word(_ v: JSONValue) -> String {
        switch v {
        case .string(let s): s
        case .bool(let b): b ? "true" : "false"
        case .number(let n): n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        default: string(v)
        }
    }

    static func string(_ v: JSONValue) -> String { String(decoding: encode(v) ?? Data(), as: UTF8.self) }

    static func encode(_ v: JSONValue) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(v)
    }
}

private final class Output: @unchecked Sendable {
    var items: [(String, JSONValue)] = []
    func add(_ key: String, _ value: JSONValue) { items.append((key, value)) }
    func lines(_ key: String) -> [String] {
        items.compactMap { k, v in
            guard k == key, case .string(let s) = v else { return nil }
            return s
        }
    }
}
