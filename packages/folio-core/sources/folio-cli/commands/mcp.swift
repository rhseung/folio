import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

/// `folio mcp`: the same actions and read commands as MCP tools over standard input and output.
/// The client starts it per session, so there is no server to keep running.
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
    /// Every action and read command, listed or not: what `action_search` finds and `action_run` runs.
    let catalog: [Tool]

    init(gist: String?, propose: Bool) {
        self.gist = gist
        self.propose = propose
        let all = Self.writeTools(propose: propose) + Self.readTools().map { Self.builds[$0.command] == nil ? $0 : Self.writing($0, propose: propose) }
        catalog = all
        tools = (propose ? all.filter { Self.inPanel($0.command) } : all) + Self.generalTools(propose: propose)
    }

    /// Commands written by hand that write by building one action (`add` reads a quick-add line into `assignment add`).
    /// Read off the help like a read command, they would otherwise be marked read-only and skip `--dry-run` under
    /// `--propose`. The action they build is the one proposed.
    static let builds: [String: String] = ["add": "assignment add"]

    static func writing(_ tool: Tool, propose: Bool) -> Tool {
        var t = tool
        t.write = true
        t.spec["annotations"] = ["readOnlyHint": .bool(false), "destructiveHint": .bool(false), "openWorldHint": .bool(false)]
        if !propose { t.spec["inputSchema"]?["properties"]?["dryRun"] = ["type": "boolean", "description": .string(String(localized: .mcpDryRunHelp))] }
        return t
    }

    /// What the app's Claude panel (`--propose`) opens: the tools for talking about one course. Every tool's
    /// definition goes with every question, so imports, backups, cleanup, settings, the transcript and the like
    /// would cost tokens on each one without being used there. The terminal's `folio mcp` keeps them all.
    static let panelGroups: Set<String> = [
        "note", "session", "unit", "exam", "assignment", "material", "quiz", "score", "component", "attendance", "review",
        "problem-set", "search", "today",
    ]
    static let panelCommands: Set<String> = ["course show", "course list"]

    static func inPanel(_ command: String) -> Bool {
        panelCommands.contains(command) || command.split(separator: " ").first.map { panelGroups.contains(String($0)) } == true
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
                "serverInfo": ["name": "folio", "version": .string(FolioVersion.marketing)],
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
        switch tool.name {
        case Self.searchTool: return search(arguments)
        case Self.runTool: return runAny(arguments)
        default: break
        }
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
        let text = Self.compact((code == 0 ? out.lines("out") : out.lines("err") + out.lines("out")).joined(separator: "\n"))
        var content: [JSONValue] = [["type": "text", "text": .string(text)]]
        // What the panel shows an approve button for: the action with every name already resolved to its UUID.
        if code == 0, tool.write, propose, let input = built.items.first(where: { $0.0 == (Self.builds[tool.command] ?? tool.command) })?.1 {
            // In the result too: the app replaces the system prompt, so the server's instructions may never reach Claude.
            content.insert(["type": "text", "text": .string(String(localized: .mcpInstructionsPropose))], at: 0)
            content.append(["type": "text", "text": .string(ActionProposal(command: Self.builds[tool.command] ?? tool.command, input: input).text)])
        }
        return ["content": .array(content), "isError": .bool(code != 0)]
    }

    // MARK: Any action

    static let searchTool = "action_search"
    static let runTool = "action_run"

    /// The way to every action the panel doesn't list. Opening all of them would send some 20k tokens of definitions
    /// with each question; leaning on the client's own deferred tool loading would tie the panel to how that works.
    /// The app's panel names these two in its progress line (`ClaudeModel.toolLabel`), which can't link this module.
    static func generalTools(propose: Bool) -> [Tool] {
        var run: JSONValue = [
            "action": ["type": "string", "description": .string(String(localized: .mcpRunActionHelp))],
            "input": ["type": "object", "description": .string(String(localized: .mcpRunInputHelp))],
        ]
        if !propose { run["dryRun"] = ["type": "boolean", "description": .string(String(localized: .mcpDryRunHelp))] }
        let search: JSONValue = [
            "name": .string(searchTool),
            "title": .string(String(localized: .mcpSearchTitle)),
            "description": .string(String(localized: .mcpSearchDescription)),
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": .string(String(localized: .mcpSearchQueryHelp))],
                    "limit": ["type": "integer", "minimum": .number(1), "maximum": .number(Double(searchMost))],
                ],
                "required": .array(["query"]),
            ],
            "annotations": ["readOnlyHint": .bool(true), "openWorldHint": .bool(false)],
        ]
        let runSpec: JSONValue = [
            "name": .string(runTool),
            "title": .string(String(localized: .mcpRunTitle)),
            "description": .string(String(localized: .mcpRunDescription) + " " + String(localized: .mcpRemovesNote)),
            "inputSchema": ["type": "object", "properties": run, "required": .array(["action"])],
            "annotations": ["readOnlyHint": .bool(false), "destructiveHint": .bool(true), "openWorldHint": .bool(false)],
        ]
        return [
            Tool(name: searchTool, command: "", write: false, spec: search) { _ in [] },
            Tool(name: runTool, command: "", write: true, spec: runSpec) { _ in [] },
        ]
    }

    static let searchMost = 10

    /// `folio help <request>`'s ranking, kept to what `action_run` can run, with each one's input schema.
    func search(_ arguments: JSONValue) -> JSONValue {
        guard case .string(let query)? = arguments["query"], !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Self.failure(String(localized: .mcpSearchNoQuery))
        }
        // Clamped as a Double: `Int(1e300)` traps and would end the server.
        let limit = if case .number(let n)? = arguments["limit"] { Int(min(max(n, 1), Double(Self.searchMost))) } else { 5 }
        let listed = Set(tools.map(\.name))
        // Asked for more than shown: some matches are commands that aren't tools (`run`, `unlock`) and drop out.
        let found = Finder.find(query, limit: Self.searchMost * 2).compactMap { m -> JSONValue? in
            let command = String(m.command.dropFirst("folio ".count))
            guard let t = catalog.first(where: { $0.command == command }) else { return nil }
            var one: JSONValue = [
                "command": .string(command), "summary": t.spec["description"] ?? .string(m.abstract), "write": .bool(t.write),
                "inputSchema": t.spec["inputSchema"] ?? [:], "examples": .array(m.examples.map(JSONValue.string)),
            ]
            if listed.contains(t.name) { one["tool"] = .string(t.name) }
            return one
        }.prefix(limit)
        guard !found.isEmpty else { return Self.failure(String(localized: .finderNoMatch(query))) }
        return ["content": .array([["type": "text", "text": .string(Self.string(Self.pruned(.array(Array(found)))))]]), "isError": .bool(false)]
    }

    /// Runs one catalog entry as its own tool would, so writes are dry runs and proposals under `--propose`, and the
    /// grades lock is the command's own.
    func runAny(_ arguments: JSONValue) -> JSONValue {
        guard case .string(let given)? = arguments["action"] else { return Self.failure(String(localized: .mcpRunNoAction)) }
        let name = given.trimmingCharacters(in: .whitespaces).replacing(/^folio\s+/, with: "")
        guard let tool = catalog.first(where: { $0.command == name || $0.name == name }) else {
            return Self.failure(String(localized: .mcpRunUnknown(name)))
        }
        var input = arguments["input"] ?? [:]
        guard case .object = input else { return Self.failure(String(localized: .runNotObject)) }
        if arguments["dryRun"] == .bool(true) { input["dryRun"] = .bool(true) }
        return call(tool, input)
    }

    static func failure(_ text: String) -> JSONValue {
        ["content": .array([["type": "text", "text": .string(text)]]), "isError": .bool(true)]
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
    static let notTools: Set<String> = ["actions", "run", "skill", "completion", "mcp", "unlock", "lock", "cleanup plan", "help", "open"]
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

    /// `--json` output as Claude reads it: one line, without the nulls and empty lists that made up most of a
    /// pretty-printed `session list`. Text that isn't a JSON object or array, such as an error, stays as it is.
    static func compact(_ text: String) -> String {
        guard let first = text.first(where: { !$0.isWhitespace }), first == "{" || first == "[",
              let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else { return text }
        return string(pruned(value))
    }

    /// Drops object members that say nothing. Array elements stay even when empty, so positions keep their meaning.
    static func pruned(_ v: JSONValue) -> JSONValue {
        switch v {
        case .object(let o):
            return .object(o.compactMapValues { member in
                switch pruned(member) {
                case .null: nil
                case .array(let a) where a.isEmpty: nil
                case .object(let o) where o.isEmpty: nil
                case let p: p
                }
            })
        case .array(let a): return .array(a.map(pruned))
        default: return v
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
