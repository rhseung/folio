import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct MCPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp", abstract: String(localized: .mcpAbstract), discussion: String(localized: .mcpDiscussion))

    @Option(help: ArgumentHelp(String(localized: .globalOptionsHelpGist), valueName: "path")) var gist: String?
    @Flag(help: ArgumentHelp(String(localized: .mcpHelpPropose))) var propose = false

    func run() throws {
        let server = MCPServer(gist: gist, propose: propose)
        // stdout이 프로토콜을 실으므로 답은 `print`의 버퍼를 거치지 않고 바로 쓴다.
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
    let stage: ProposalStage?
    let tools: [Tool]
    let catalog: [Tool]

    init(gist: String?, propose: Bool) {
        self.gist = gist
        self.propose = propose
        stage = propose ? ProposalStage() : nil
        let all =
            Self.writeTools(propose: propose)
            + Self.readTools().map { Self.builds[$0.command] == nil ? $0 : Self.writing($0, propose: propose) }
        catalog = all
        tools = (propose ? all.filter { Self.inPanel($0.command) } : all) + Self.generalTools(propose: propose)
    }

    // 도움말에서 읽으면 읽기 명령처럼 읽기 전용으로 표시되어 `--propose`에서 `--dry-run`을 건너뛴다. 그래서 액션 하나를
    // 만들어 쓰는 손 명령을 여기 적고, 만든 액션을 제안한다.
    static let builds: [String: String] = ["add": "assignment add"]

    static func writing(_ tool: Tool, propose: Bool) -> Tool {
        var t = tool
        t.write = true
        t.spec["annotations"] = ["readOnlyHint": .bool(false), "destructiveHint": .bool(false), "openWorldHint": .bool(false)]
        if !propose {
            t.spec["inputSchema"]?["properties"]?["dryRun"] = [
                "type": "boolean", "description": .string(String(localized: .mcpDryRunHelp)),
            ]
        }
        return t
    }

    static let panelGroups: Set<String> = [
        "note", "session", "unit", "exam", "assignment", "material", "quiz", "score", "component", "attendance", "review",
        "problem-set", "search", "today",
    ]
    static let panelCommands: Set<String> = ["course show", "course list", "recording transcript"]

    static func inPanel(_ command: String) -> Bool {
        panelCommands.contains(command) || command.split(separator: " ").first.map { panelGroups.contains(String($0)) } == true
    }

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
            return Self.encode([
                "jsonrpc": "2.0", "id": id, "error": ["code": .number(-32601), "message": .string("unknown method: \(method)")],
            ])
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

        let command = Self.builds[tool.command] ?? tool.command
        if propose, let stage { return proposing(tool, command, argv, stage) }
        let run = Self.execute(argv)
        return Self.result(run.code == 0 ? run.out : run.err + run.out, failed: run.code != 0, pictures: run.pictures)
    }

    // `--propose`에서 쓰기는 답의 사본에서 두 번 돈다. 거절할 수 있는 dry run으로 한 번, 그다음 실제로 한 번이다. 그래야
    // 거절된 쓰기가 다음 쓰기가 기댈 반쯤 쓴 상태를 남기지 않는다. 사본이 생긴 뒤에는 읽기도 사본에서 돌아 제안한 것을
    // 본다. `search`의 색인은 폴더의 것이므로 `search`는 폴더에서 돈다.
    func proposing(_ tool: Tool, _ command: String, _ argv: [String], _ stage: ProposalStage) -> JSONValue {
        guard tool.write else {
            let folder = command == "search" ? nil : stage.folder
            let run = Self.execute(argv, staging: folder.map { Staging(folder: $0, writes: false) })
            guard run.code == 0 else { return Self.result(run.err + run.out, failed: true) }
            var text = Self.compact(run.out, marking: stage)
            guard folder != nil, stage.staged > 0 else {
                return Self.result([text], failed: false, compacted: true, pictures: run.pictures)
            }
            let pictures = Self.images(&text)
            return [
                "content": .array(
                    [
                        ["type": "text", "text": .string(String(localized: .mcpStagedRead(stage.staged)))],
                        ["type": "text", "text": .string(text)],
                    ] + pictures + Self.labeled(run.pictures)), "isError": .bool(false),
            ]
        }

        let real = try? CLI.gist(path: gist).url
        let folder = real.flatMap(stage.copy(of:))
        let stages = folder != nil && ActionProposal.stages(command)
        var run = Self.execute(argv, staging: folder.map { Staging(folder: $0, writes: false) })
        if run.code == 0, stages, let folder { run = Self.execute(argv, staging: Staging(folder: folder, writes: true)) }
        guard run.code == 0, let input = run.built.first(where: { $0.0 == command })?.1 else {
            return Self.result(run.code == 0 ? run.out : run.err + run.out, failed: run.code != 0)
        }

        let after = stage.staged > 0 && Self.execute(argv).code != 0 ? stage.earlier(input) : []
        stage.record(stages ? ProposalStage.made(from: run.out.joined(separator: "\n")) : ProposalStage.Made(items: [:], paths: []))
        var content: [JSONValue] = [["type": "text", "text": .string(Self.compact(run.out.joined(separator: "\n")))]]
        // 앱이 시스템 프롬프트를 바꾸므로 서버의 지시가 Claude에 닿지 않을 수 있어, 결과에도 넣는다.
        content.insert(["type": "text", "text": .string(String(localized: .mcpInstructionsPropose))], at: 0)
        content.append([
            "type": "text", "text": .string(ActionProposal(command: command, input: input, after: after.isEmpty ? nil : after).text),
        ])
        return ["content": .array(content), "isError": .bool(false)]
    }

    struct Run {
        var code: Int32
        var out: [String]
        var err: [String]
        var built: [(String, JSONValue)]
        var pictures: [Pictures.Picture] = []
    }

    static func execute(_ argv: [String], staging: Staging? = nil) -> Run {
        let out = Output()
        let built = Output()
        let pictures = Pictures()
        let code = Pictures.$current.withValue(pictures) {
            CLI.$staging.withValue(staging) {
                Built.$record.withValue({ command, input in built.add(command, input) }) {
                    Sink.$current.withValue(Sink(out: { out.add("out", .string($0)) }, err: { out.add("err", .string($0)) })) {
                        if let staging { return staging.folder.run { Folio.run(argv) } }
                        return Folio.run(argv)
                    }
                }
            }
        }
        return Run(code: code, out: out.lines("out"), err: out.lines("err"), built: built.items, pictures: code == 0 ? pictures.items : [])
    }

    static func result(_ lines: [String], failed: Bool, compacted: Bool = false, pictures read: [Pictures.Picture] = []) -> JSONValue {
        var text = lines.joined(separator: "\n")
        let pictures = failed ? [] : images(&text)
        return [
            "content": .array([["type": "text", "text": .string(compacted ? text : compact(text))]] + pictures + labeled(read)),
            "isError": .bool(failed),
        ]
    }

    static func labeled(_ pictures: [Pictures.Picture]) -> [JSONValue] {
        pictures.flatMap { p -> [JSONValue] in
            [
                ["type": "text", "text": .string(p.label)],
                ["type": "image", "data": .string(p.data.base64EncodedString()), "mimeType": .string(p.mimeType)],
            ]
        }
    }

    static func compact(_ lines: [String], marking stage: ProposalStage) -> String {
        let text = lines.joined(separator: "\n")
        guard let first = text.first(where: { !$0.isWhitespace }), first == "{" || first == "[",
            let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        else { return text }
        return string(pruned(stage.marked(value)))
    }

    // MARK: Any action

    static let searchTool = "action_search"
    static let runTool = "action_run"

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

    func search(_ arguments: JSONValue) -> JSONValue {
        guard case .string(let query)? = arguments["query"], !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Self.failure(String(localized: .mcpSearchNoQuery))
        }
        // `Int(1e300)`은 멈춰 서버를 끝내므로 Double로 자른다.
        let limit = if case .number(let n)? = arguments["limit"] { Int(min(max(n, 1), Double(Self.searchMost))) } else { 5 }
        let listed = Set(tools.map(\.name))
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
        return [
            "content": .array([["type": "text", "text": .string(Self.string(Self.pruned(.array(Array(found)))))]]), "isError": .bool(false),
        ]
    }

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

    static func images(_ text: inout String) -> [JSONValue] {
        guard text.contains("\"png\""), let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
            case .array(let items)? = value["images"]
        else { return [] }
        var found: [JSONValue] = []
        var rest = value
        rest["images"] = .array(
            items.map { item in
                guard case .string(let png)? = item["png"] else { return item }
                found.append(["type": "image", "data": .string(png), "mimeType": "image/png"])
                var described = item
                described["png"] = nil
                return described
            })
        text = string(rest)
        return found
    }

    static func failure(_ text: String) -> JSONValue {
        ["content": .array([["type": "text", "text": .string(text)]]), "isError": .bool(true)]
    }

    // MARK: Tools

    static func name(_ command: String) -> String {
        command.replacing(" --", with: "_").replacing(" ", with: "_")
    }

    static func writeTools(propose: Bool) -> [Tool] {
        guard case .object(let all) = actionSchemas(), case .array(let actions)? = all["actions"], case .object(let defs)? = all["$defs"]
        else { return [] }
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
        func key(_ a: Help.Argument) -> String {
            a.kind == "positional" ? (a.valueName ?? "value") : a.preferredName?.name ?? a.valueName ?? "value"
        }
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
            // `--` 뒤에 두어야 `-1` 같은 이름이 옵션이 아니라 값으로 남는다.
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

    static func compact(_ text: String) -> String {
        guard let first = text.first(where: { !$0.isWhitespace }), first == "{" || first == "[",
            let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        else { return text }
        return string(pruned(value))
    }

    // 배열의 위치가 뜻을 지키도록 배열 요소는 비어 있어도 남긴다.
    static func pruned(_ v: JSONValue) -> JSONValue {
        switch v {
        case .object(let o):
            return .object(
                o.compactMapValues { member in
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
