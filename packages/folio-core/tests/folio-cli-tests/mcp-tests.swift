@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

struct MCPTests {
    let h = Harness()

    func send(_ server: MCPServer, _ gist: URL, _ method: String, _ params: JSONValue = [:]) throws -> JSONValue {
        let line = MCPServer.string(["jsonrpc": "2.0", "id": .number(1), "method": .string(method), "params": params])
        let reply = CLI.$overrides.withValue(Overrides(gist: gist, device: h.device, now: h.now)) { server.handle(line) }
        return try JSONDecoder().decode(JSONValue.self, from: try #require(reply))
    }

    func call(_ server: MCPServer, _ gist: URL, _ name: String, _ arguments: JSONValue) throws -> (Bool, [String]) {
        let result = try #require(try send(server, gist, "tools/call", ["name": .string(name), "arguments": arguments])["result"])
        guard case .array(let blocks)? = result["content"] else { return (true, []) }
        let texts = blocks.compactMap { b -> String? in if case .string(let s)? = b["text"] { s } else { nil } }
        return (result["isError"] == .bool(true), texts)
    }

    @Test func everyActionIsATool() throws {
        let gist = try Harness.fixtureCopy()
        let server = MCPServer(gist: nil, propose: false)
        guard case .array(let tools)? = try send(server, gist, "tools/list")["result"]?["tools"] else { Issue.record("no tools"); return }
        let names = Set(tools.compactMap { t -> String? in if case .string(let n)? = t["name"] { n } else { nil } })
        for type in Actions.all { #expect(names.contains(MCPServer.name(type.command)), "\(type.command) has no tool") }
        for read in ["today", "exam_list", "note_show", "search", "gpa"] { #expect(names.contains(read)) }
        for tool in ["run", "mcp", "skill", "unlock", "cleanup_plan"] { #expect(!names.contains(tool)) }
        // Each tool's schema stands alone: clients don't share `$defs` between tools.
        for t in tools {
            guard let schema = t["inputSchema"] else { continue }
            let defs: [String: JSONValue] = if case .object(let d)? = schema["$defs"] { d } else { [:] }
            for ref in MCPServer.referenced(schema, defs) { #expect(defs[ref] != nil, "\(t["name"]!) misses \(ref)") }
        }
    }

    func toolNames(_ server: MCPServer, _ gist: URL) throws -> Set<String> {
        guard case .array(let tools)? = try send(server, gist, "tools/list")["result"]?["tools"] else { return [] }
        return Set(tools.compactMap { t -> String? in if case .string(let n)? = t["name"] { n } else { nil } })
    }

    @Test func thePanelOpensOnlyTheCourseTools() throws {
        let gist = try Harness.fixtureCopy()
        let panel = try toolNames(MCPServer(gist: nil, propose: true), gist)
        let all = try toolNames(MCPServer(gist: nil, propose: false), gist)
        #expect(panel.isSubset(of: all))
        for tool in ["note_edit", "note_write", "note_show", "session_list", "exam_scope_taught", "attendance_set", "review_record",
                     "problem-set_record", "search", "today", "course_show", "course_list"] {
            #expect(panel.contains(tool), "\(tool) is not in the panel")
        }
        for tool in ["import_notion", "backup_create", "cleanup_apply", "settings_set", "catalog_show", "transcript_show", "requirement_check",
                     "semester_add", "gpa", "recording_trim", "course_add", "course_rename", "course_set", "check"] {
            #expect(!panel.contains(tool), "\(tool) is in the panel")
            #expect(all.contains(tool), "\(tool) left the terminal's tools")
        }
    }

    @Test func readResultsAreCompactJSON() throws {
        let gist = try Harness.fixtureCopy()
        // The fixture's note has empty `sessionIds` and `unitIds`, printed over several lines.
        let (failed, texts) = try call(MCPServer(gist: nil, propose: true), gist, "note_list", ["course": "EC4207"])
        #expect(!failed, "\(texts)")
        let text = try #require(texts.first)
        #expect(text.contains("\"path\""))
        #expect(!text.contains("\n") && !text.contains("[]") && !text.contains("null") && !text.contains("{}"), "\(text)")
        #expect((try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) != nil)
    }

    @Test func compactingDropsOnlyEmptyMembers() {
        let pretty = "{\n  \"a\" : [\n    {}, null, 0\n  ],\n  \"b\" : null,\n  \"c\" : { \"d\" : [], \"e\" : {} },\n  \"f\" : \"\",\n  \"g\" : false\n}"
        #expect(MCPServer.compact(pretty) == #"{"a":[{},null,0],"f":"","g":false}"#)
        #expect(MCPServer.compact("노트가 없습니다: a") == "노트가 없습니다: a")
        #expect(MCPServer.compact("[not json") == "[not json")
        #expect(MCPServer.compact("42") == "42")
    }

    @Test func aProposedNoteEditCarriesOnlyTheChange() throws {
        let (a, b) = (try Harness.fixtureCopy(), try Harness.fixtureCopy())
        let before = try Harness.files(a)
        let input: JSONValue = ["course": "EC4207", "note": "2주차-1", "replacements": .array([["old": "Matching", "new": "매칭"]]), "append": "질문"]
        let (failed, texts) = try call(MCPServer(gist: nil, propose: true), a, "note_edit", input)
        #expect(!failed, "\(texts)")
        #expect(try Harness.files(a) == before)
        #expect(texts.first?.contains("note_edit") == true)
        let proposal = try #require(texts.compactMap(ActionProposal.init(text:)).first)
        #expect(proposal.command == "note edit")
        let type = try #require(Actions.all.first { $0.command == proposal.command })
        try h.direct(try type.decode(JSONEncoder().encode(proposal.input)), gist: b)
        let r = h.cli(["note", "show", "EC4207/2주차-1"], gist: b)
        #expect(r.out.contains("> [!definition] 매칭") && r.out.contains("edges.\n질문"), "\(r.out)")
        let missing = try call(MCPServer(gist: nil, propose: true), a, "note_edit", ["course": "EC4207", "note": "2주차-1", "append": ""])
        #expect(missing.0)
    }

    @Test func writesThroughTheSameRun() throws {
        let (a, b) = (try Harness.fixtureCopy(), try Harness.fixtureCopy())
        let input: JSONValue = ["course": "EC4207", "title": "중간고사 대비 퀴즈", "location": "A동"]
        let (failed, texts) = try call(MCPServer(gist: nil, propose: false), a, "exam_add", input)
        #expect(!failed, "\(texts)")
        let r = h.cli(["exam", "add", "EC4207", "중간고사 대비 퀴즈", "--location", "A동"], gist: b)
        #expect(r.code == 0, "\(r.err)")
        let (fa, fb) = (try Harness.files(a), try Harness.files(b))
        #expect(fa.keys.sorted() == fb.keys.sorted())
        for (path, data) in fa { #expect(Harness.canonical(fb[path]) == Harness.canonical(data), "\(path)") }
    }

    @Test func readsWithPositionalsAndOptions() throws {
        let gist = try Harness.fixtureCopy()
        let server = MCPServer(gist: nil, propose: false)
        let (failed, texts) = try call(server, gist, "assignment_list", ["course": "EC4207", "all": .bool(true)])
        #expect(!failed, "\(texts)")
        #expect((try? JSONDecoder().decode(JSONValue.self, from: Data(texts.joined().utf8))) != nil)
        let missing = try call(server, gist, "exam_show", ["exam": "EC4207/없는 시험"])
        #expect(missing.0)
    }

    @Test func proposingLeavesFilesAndHandsBackTheAction() throws {
        let (a, b) = (try Harness.fixtureCopy(), try Harness.fixtureCopy())
        let before = try Harness.files(a)
        let (failed, texts) = try call(MCPServer(gist: nil, propose: true), a, "exam_add",
                                       ["course": "EC4207", "title": "제안 퀴즈", "location": "B동"])
        #expect(!failed, "\(texts)")
        #expect(try Harness.files(a) == before)
        let proposal = try #require(texts.compactMap(ActionProposal.init(text:)).first)
        #expect(proposal.command == "exam add")
        let type = try #require(Actions.all.first { $0.command == proposal.command })
        try h.direct(try type.decode(JSONEncoder().encode(proposal.input)), gist: b)
        let r = h.cli(["exam", "show", "EC4207/제안 퀴즈", "--json"], gist: b)
        #expect(r.code == 0, "\(r.err)")
    }

    @Test func protocolEdges() throws {
        let gist = try Harness.fixtureCopy()
        let server = MCPServer(gist: nil, propose: false)
        #expect(try send(server, gist, "initialize", ["protocolVersion": "2024-11-05"])["result"]?["protocolVersion"] == "2024-11-05")
        #expect(try send(server, gist, "nope")["error"]?["code"] == .number(-32601))
        #expect(server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(server.handle("not json").flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }?["error"]?["code"] == .number(-32700))
    }
}
