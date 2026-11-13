import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import FolioCLI

struct MCPTests {
    let h = Harness()

    func send(_ server: MCPServer, _ gist: URL, _ method: String, _ params: JSONValue = [:], unlocked: Bool = true) throws -> JSONValue {
        let line = MCPServer.string(["jsonrpc": "2.0", "id": .number(1), "method": .string(method), "params": params])
        let reply = CLI.$overrides.withValue(Overrides(gist: gist, device: h.device, now: h.now, gradesUnlocked: unlocked)) {
            server.handle(line)
        }
        return try JSONDecoder().decode(JSONValue.self, from: try #require(reply))
    }

    func call(_ server: MCPServer, _ gist: URL, _ name: String, _ arguments: JSONValue, unlocked: Bool = true) throws -> (Bool, [String]) {
        let result = try #require(
            try send(server, gist, "tools/call", ["name": .string(name), "arguments": arguments], unlocked: unlocked)["result"])
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
        for tool in [
            "note_edit", "note_write", "note_show", "session_list", "exam_scope_taught", "attendance_set", "review_record",
            "problem-set_record", "search", "today", "course_show", "course_list", "note_figure_add", "note_figure_write",
            "note_figure_render", "note_widget_add", "note_widget_write", "note_widget_render", "note_format",
        ] {
            #expect(panel.contains(tool), "\(tool) is not in the panel")
        }
        for tool in [
            "import_notion", "backup_create", "cleanup_apply", "settings_set", "catalog_show", "transcript_show", "requirement_check",
            "semester_add", "gpa", "recording_trim", "course_add", "course_rename", "course_set", "check",
        ] {
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
        let pretty =
            "{\n  \"a\" : [\n    {}, null, 0\n  ],\n  \"b\" : null,\n  \"c\" : { \"d\" : [], \"e\" : {} },\n  \"f\" : \"\",\n  \"g\" : false\n}"
        #expect(MCPServer.compact(pretty) == #"{"a":[{},null,0],"f":"","g":false}"#)
        #expect(MCPServer.compact("노트가 없습니다: a") == "노트가 없습니다: a")
        #expect(MCPServer.compact("[not json") == "[not json")
        #expect(MCPServer.compact("42") == "42")
    }

    @Test func aProposedNoteEditCarriesOnlyTheChange() throws {
        let (a, b) = (try Harness.fixtureCopy(), try Harness.fixtureCopy())
        let before = try Harness.files(a)
        let input: JSONValue = [
            "course": "EC4207", "note": "09-08", "replacements": .array([["old": "Matching", "new": "매칭"]]), "append": "질문",
        ]
        let (failed, texts) = try call(MCPServer(gist: nil, propose: true), a, "note_edit", input)
        #expect(!failed, "\(texts)")
        #expect(try Harness.files(a) == before)
        #expect(texts.first?.contains("note_edit") == true)
        let proposal = try #require(texts.compactMap(ActionProposal.init(text:)).first)
        #expect(proposal.command == "note edit")
        let type = try #require(Actions.all.first { $0.command == proposal.command })
        try h.direct(try type.decode(JSONEncoder().encode(proposal.input)), gist: b)
        let r = h.cli(["note", "show", "EC4207/09-08"], gist: b)
        #expect(r.out.contains("> [!definition] 매칭") && r.out.contains("edges.\n질문"), "\(r.out)")
        let missing = try call(MCPServer(gist: nil, propose: true), a, "note_edit", ["course": "EC4207", "note": "09-08", "append": ""])
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
        let (failed, texts) = try call(
            MCPServer(gist: nil, propose: true), a, "exam_add",
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

    @Test func bothServersOpenTheGeneralTools() throws {
        let gist = try Harness.fixtureCopy()
        for propose in [true, false] {
            let names = try toolNames(MCPServer(gist: nil, propose: propose), gist)
            #expect(names.contains("action_search") && names.contains("action_run"), "propose: \(propose)")
        }
    }

    func found(_ server: MCPServer, _ gist: URL, _ query: String) throws -> [JSONValue] {
        let (failed, texts) = try call(server, gist, "action_search", ["query": .string(query)])
        #expect(!failed, "\(texts)")
        let text = try #require(texts.first)
        #expect(!text.contains("\n") && !text.contains("null"), "\(text)")
        guard case .array(let matches) = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else { return [] }
        return matches
    }

    @Test func searchFindsActionsOutsideThePanelWithTheirSchema() throws {
        let gist = try Harness.fixtureCopy()
        let panel = MCPServer(gist: nil, propose: true)
        let semester = try #require(try found(panel, gist, "새 학기 만들기").first { $0["command"] == "semester add" })
        #expect(semester["inputSchema"]?["properties"]?["year"] != nil)
        #expect(semester["write"] == .bool(true))

        // Not listed in the panel, so it goes through action_run.
        #expect(semester["tool"] == nil)
        let exam = try #require(try found(panel, gist, "시험 추가").first { $0["command"] == "exam add" })
        #expect(exam["tool"] == "exam_add")

        // Only what action_run can run: `unlock` is a command but never a tool.
        let unlock = try found(MCPServer(gist: nil, propose: false), gist, "성적 보이게 해줘")
        #expect(!unlock.contains { $0["command"] == "unlock" })
        #expect(try call(panel, gist, "action_search", ["query": ""]).0)

        // A limit past Int's range is clamped rather than ending the server.
        let (huge, texts) = try call(panel, gist, "action_search", ["query": "시험 추가", "limit": .number(1e300)])
        #expect(!huge, "\(texts)")
    }

    @Test func runningAnyActionInThePanelOnlyProposes() throws {
        let (a, b) = (try Harness.fixtureCopy(), try Harness.fixtureCopy())
        let before = try Harness.files(a)
        let input: JSONValue = ["year": .number(2027), "term": "spring", "start": "2027-03-02"]
        let (failed, texts) = try call(
            MCPServer(gist: nil, propose: true), a, "action_run", ["action": "semester add", "input": input, "dryRun": .bool(false)])
        #expect(!failed, "\(texts)")
        #expect(try Harness.files(a) == before)
        let proposal = try #require(texts.compactMap(ActionProposal.init(text:)).first)
        #expect(proposal.command == "semester add")
        let type = try #require(Actions.all.first { $0.command == proposal.command })
        try h.direct(try type.decode(JSONEncoder().encode(proposal.input)), gist: b)
        #expect(h.cli(["semester", "show", "2027-1", "--json"], gist: b).code == 0)
    }

    @Test func runningInTheTerminalWritesOrDryRuns() throws {
        let (a, b) = (try Harness.fixtureCopy(), try Harness.fixtureCopy())
        let server = MCPServer(gist: nil, propose: false)
        let before = try Harness.files(a)
        let args: JSONValue = ["action": "settings_set", "input": ["field": "dayBoundaryMinutes", "value": .number(300)]]
        var dry = args
        dry["dryRun"] = .bool(true)
        let (dryFailed, dryTexts) = try call(server, a, "action_run", dry)
        #expect(!dryFailed, "\(dryTexts)")
        #expect(try Harness.files(a) == before)
        #expect(dryTexts.compactMap(ActionProposal.init(text:)).isEmpty)
        let (failed, texts) = try call(server, a, "action_run", args)
        #expect(!failed, "\(texts)")
        #expect(h.cli(["settings", "set", "dayBoundaryMinutes", "300"], gist: b).code == 0)
        let (fa, fb) = (try Harness.files(a), try Harness.files(b))
        #expect(fa != before)
        for (path, data) in fa { #expect(Harness.canonical(fb[path]) == Harness.canonical(data), "\(path)") }
    }

    @Test func runningReadsCommandsAndKeepsTheGradesLock() throws {
        let gist = try Harness.fixtureCopy()
        let panel = MCPServer(gist: nil, propose: true)
        let (failed, texts) = try call(panel, gist, "action_run", ["action": "folio settings show"])
        #expect(!failed, "\(texts)")
        #expect(texts.first?.contains("dayBoundaryMinutes") == true, "\(texts)")
        #expect(try call(panel, gist, "action_run", ["action": "gpa"]).0 == false)

        // The owner didn't unlock: the command's own Touch ID check refuses, as in the terminal.
        let locked = try call(panel, gist, "action_run", ["action": "gpa"], unlocked: false)
        #expect(locked.0, "\(locked.1)")
        #expect(try call(panel, gist, "action_run", ["action": "unlock"]).0)
        #expect(try call(panel, gist, "action_run", ["action": "settings set", "input": "not an object"]).0)
        #expect(try call(panel, gist, "action_run", [:]).0)
    }

    func proposals(_ texts: [String]) -> [ActionProposal] { texts.compactMap(ActionProposal.init(text:)) }

    func apply(_ proposal: ActionProposal, to gist: URL) throws {
        let type = try #require(Actions.all.first { $0.command == proposal.command })
        try h.direct(try type.decode(JSONEncoder().encode(proposal.input)), gist: gist)
    }

    /// #90: one answer's proposals stack in a staged copy, so a write that needs an earlier proposal passes.
    @Test func aUnitsPagesBuildOnTheUnitProposedBeforeThem() throws {
        let a = try Harness.fixtureCopy()
        #expect(h.cli(LectureSectionCommandTests.track, gist: a).code == 0)

        // Tracked once and copied: tracking twice would give the lecture two different ids.
        let b = FileManager.default.temporaryDirectory.appending(path: "folio-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: a, to: b)
        let before = try Harness.files(a)
        let server = MCPServer(gist: nil, propose: true)
        let unit = try call(server, a, "unit_add", ["course": "EC4207", "title": "König"])
        #expect(!unit.0, "\(unit.1)")
        let pages = try call(
            server, a, "unit_pages_add",
            [
                "course": "EC4207", "unit": "König", "material": "05_Matchings.pdf",
                "first": .number(5), "last": .number(8),
            ])
        #expect(!pages.0, "\(pages.1)")
        let (first, second) = (try #require(proposals(unit.1).first), try #require(proposals(pages.1).first))
        #expect(first.after == nil)
        #expect(second.after == [0])

        // Read back in the same answer, marked as not yet approved.
        let shown = try call(server, a, "unit_show", ["unit": "EC4207/König"])
        #expect(!shown.0, "\(shown.1)")
        #expect(shown.1.joined().contains("\"proposed\":\"added\""), "\(shown.1)")
        #expect(shown.1.joined().contains("firstPage"), "\(shown.1)")
        #expect(try Harness.files(a) == before)

        // Applied in order, they make what the answer read.
        try apply(first, to: b)
        try apply(second, to: b)
        #expect(h.cli(["unit", "show", "EC4207/König"], gist: b).out.contains("05_Matchings.pdf p.5-8"))

        // The next question's server starts from the folder, without the proposals left unapproved.
        let next = MCPServer(gist: nil, propose: true)
        #expect(
            try call(
                next, a, "unit_pages_add",
                [
                    "course": "EC4207", "unit": "König", "material": "05_Matchings.pdf",
                    "first": .number(5), "last": .number(8),
                ]
            ).0)
        #expect(try call(next, a, "unit_show", ["unit": "EC4207/König"]).0)
    }

    @Test func aNoteEditBuildsOnTheNoteProposedBeforeIt() throws {
        let (a, b) = (try Harness.fixtureCopy(), try Harness.fixtureCopy())
        let before = try Harness.files(a)
        let server = MCPServer(gist: nil, propose: true)

        // An independent proposal first: the edit builds on the note only, not on this.
        let exam = try call(server, a, "exam_add", ["course": "EC4207", "title": "제안 퀴즈"])
        #expect(!exam.0, "\(exam.1)")
        let note = try call(server, a, "note_add", ["course": "EC4207", "title": "증명 모음", "body": "# 증명 모음\n\n첫 줄\n"])
        #expect(!note.0, "\(note.1)")
        let edit = try call(
            server, a, "note_edit",
            [
                "course": "EC4207", "note": "증명 모음",
                "replacements": .array([["old": "첫 줄", "new": "고친 줄"]]), "append": "덧붙인 줄",
            ])
        #expect(!edit.0, "\(edit.1)")
        let made = try proposals(exam.1) + proposals(note.1) + proposals(edit.1)
        #expect(made.count == 3)
        #expect(made[1].after == nil)
        #expect(made[2].after == [1])
        let shown = try call(server, a, "note_show", ["note": "EC4207/증명 모음"])
        #expect(!shown.0, "\(shown.1)")
        #expect(shown.1.joined().contains("고친 줄") && shown.1.joined().contains("덧붙인 줄"), "\(shown.1)")
        #expect(try Harness.files(a) == before)
        for p in made { try apply(p, to: b) }
        let r = h.cli(["note", "show", "EC4207/증명 모음"], gist: b)
        #expect(r.out.contains("고친 줄") && r.out.contains("덧붙인 줄"), "\(r.out)")
        #expect(try call(MCPServer(gist: nil, propose: true), a, "note_edit", ["course": "EC4207", "note": "증명 모음", "append": "또"]).0)
    }

    @Test func aRefusedProposalLeavesNothingToBuildOn() throws {
        let a = try Harness.fixtureCopy()
        let server = MCPServer(gist: nil, propose: true)

        // Refused: no such note. Its dry run stops it before the copy is written.
        #expect(try call(server, a, "note_edit", ["course": "EC4207", "note": "없는 노트", "append": "x"]).0)
        let listed = try call(server, a, "note_list", ["course": "EC4207"])
        #expect(!listed.0 && !listed.1.joined().contains("proposed"), "\(listed.1)")
    }

    @Test func protocolEdges() throws {
        let gist = try Harness.fixtureCopy()
        let server = MCPServer(gist: nil, propose: false)
        #expect(try send(server, gist, "initialize", ["protocolVersion": "2024-11-05"])["result"]?["protocolVersion"] == "2024-11-05")
        #expect(try send(server, gist, "nope")["error"]?["code"] == .number(-32601))
        #expect(server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(
            server.handle("not json").flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }?["error"]?["code"] == .number(-32700))
    }
}
