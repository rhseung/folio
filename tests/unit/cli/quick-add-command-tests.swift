import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import FolioCLI

// harness의 시계는 2026-10-28 수요일 10:00이므로 `금`은 10/30이다.
struct QuickAddCommandTests {
    let h = Harness()
    let course = Harness.graphTheory
    static let robotics = UUID(uuidString: "C0000000-0000-4000-8000-000000000003")!

    func date(_ s: String) -> Date { DateArg(argument: s)!.date }

    func assignments(_ gist: URL) throws -> [Assignment] { try h.file(GISTStore(url: gist)).assignments }

    @Test func savesWhatTheLineReads() throws {
        try h.expectSame(["add", "그래프 HW5 금 23:59"]) { _ in AssignmentAdd(course: course, title: "HW5", due: date("2026-10-30 23:59")) }
        let gist = try Harness.fixtureCopy()
        let r = h.cli(["add", "그래프 HW5 금 23:59"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        for shown in ["그래프 이론", "EC4207", "HW5", "D-2", "Assignments/HW05"] { #expect(r.out.contains(shown), "\(shown) not in \(r.out)") }
        #expect(FileManager.default.fileExists(atPath: gist.appending(path: "2026-3/EC4207 그래프 이론/Assignments/HW05").path))
    }

    @Test func weeklyGoesInLikeTheApp() throws {
        try h.expectSame(["add", "로봇 매주 금요일 23:59 Weekly Quiz"]) { _ in
            AssignmentAdd(course: Self.robotics, title: "Weekly Quiz", due: date("2026-10-30 23:59"), repeats: .weekly)
        }
    }

    @Test func jsonCarriesTheReading() throws {
        let gist = try Harness.fixtureCopy()
        let r = h.cli(["add", "그래프 HW5 금 23:59", "--json", "--dry-run"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        let out = try JSONDecoder().decode(JSONValue.self, from: Data(r.out.utf8))
        #expect(out["action"] == "assignment add")
        #expect(out["dryRun"] == .bool(true))
        let read = try #require(out["read"])
        #expect(read["course"] == "EC4207")
        #expect(read["courseId"] == .string(course.uuidString))
        #expect(read["title"] == "HW5")
        #expect(read["folder"] == "Assignments/HW05")
        #expect(read["due"] != nil)
    }

    @Test func dryRunWritesNothing() throws {
        let gist = try Harness.fixtureCopy()
        let before = try Harness.files(gist)
        let r = h.cli(["add", "그래프 HW5 금 23:59", "--dry-run"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        #expect(r.out.contains("HW5"))
        #expect(try Harness.files(gist) == before)
    }

    @Test func optionsStandOverTheLine() throws {
        try h.expectSame(["add", "그래프 HW5 금 23:59", "--course", "EC4321", "--due", "2026-11-02 18:00"]) { _ in
            AssignmentAdd(course: Self.robotics, title: "HW5", due: date("2026-11-02 18:00"))
        }
        try h.expectSame(["add", "HW6 다음 주 수요일", "--course", "EC4207"]) { _ in
            AssignmentAdd(course: course, title: "HW6", due: date("2026-11-04 23:59"))
        }
        try h.expectSame(["add", "로봇 매주 금요일 23:59 Weekly Quiz", "--repeats", "none"]) { _ in
            AssignmentAdd(course: Self.robotics, title: "Weekly Quiz", due: date("2026-10-30 23:59"))
        }

        try h.expectSame(["add", "로봇 매주 금요일 23:59 Weekly Quiz", "--due", "none"]) { _ in
            AssignmentAdd(course: Self.robotics, title: "Weekly Quiz")
        }
    }

    @Test func aLineWithoutACourseWritesNothing() throws {
        let gist = try Harness.fixtureCopy()
        let before = try Harness.files(gist)

        let r = h.cli(["add", "선대 HW5 금 23:59"], gist: gist)
        #expect(r.code == Exit.notFound.rawValue)
        #expect(r.err.contains("과목을 읽지 못했습니다"), "\(r.err)")
        #expect(r.err.contains("EC4207") && r.err.contains("--course"), "\(r.err)")
        #expect(r.out.contains("읽지 못함"), "\(r.out)")
        #expect(try Harness.files(gist) == before)
        let json = h.cli(["add", "선대 HW5 금 23:59", "--json"], gist: gist)
        #expect(json.code == Exit.notFound.rawValue)
        #expect(json.err.contains("\"not_found\""), "\(json.err)")
        #expect(json.out.isEmpty)
    }

    @Test func aLineWithoutATitleWritesNothing() throws {
        let gist = try Harness.fixtureCopy()
        let before = try Harness.files(gist)
        let r = h.cli(["add", "그래프 금 23:59"], gist: gist)
        #expect(r.code == Exit.usage.rawValue)
        #expect(r.err.contains("제목을 읽지 못했습니다"), "\(r.err)")
        #expect(try Harness.files(gist) == before)
    }

    @Test func anUnknownCourseOptionWritesNothing() throws {
        let gist = try Harness.fixtureCopy()
        let before = try Harness.files(gist)
        let r = h.cli(["add", "HW5 금", "--course", "없는과목"], gist: gist)
        #expect(r.code == Exit.notFound.rawValue)
        #expect(try Harness.files(gist) == before)
    }

    // MARK: MCP

    func tools(_ server: MCPServer, _ gist: URL) throws -> [String: JSONValue] {
        let m = MCPTests()
        guard case .array(let tools)? = try m.send(server, gist, "tools/list")["result"]?["tools"] else { return [:] }
        return Dictionary(tools.compactMap { t -> (String, JSONValue)? in if case .string(let n)? = t["name"] { (n, t) } else { nil } }) {
            a, _ in a
        }
    }

    @Test func theTerminalOpensItAsAWriteTool() throws {
        let gist = try Harness.fixtureCopy()
        let server = MCPServer(gist: nil, propose: false)
        let tool = try #require(try tools(server, gist)["add"])
        #expect(tool["annotations"]?["readOnlyHint"] == .bool(false))
        #expect(tool["inputSchema"]?["properties"]?["dryRun"] != nil)
        #expect(tool["inputSchema"]?["properties"]?["line"] != nil)
        let before = try Harness.files(gist)
        let (failed, texts) = try MCPTests().call(server, gist, "add", ["line": "그래프 HW5 금 23:59", "dryRun": .bool(true)])
        #expect(!failed, "\(texts)")
        #expect(texts.joined().contains("\"read\""), "\(texts)")
        #expect(try Harness.files(gist) == before)
        let (writeFailed, _) = try MCPTests().call(server, gist, "add", ["line": "그래프 HW5 금 23:59"])
        #expect(!writeFailed)
        #expect(try assignments(gist).contains { $0.title == "HW5" })
    }

    @Test func thePanelLeavesItOut() throws {
        let gist = try Harness.fixtureCopy()
        #expect(try tools(MCPServer(gist: nil, propose: true), gist)["add"] == nil)
        #expect(try tools(MCPServer(gist: nil, propose: true), gist)["assignment_add"] != nil)
    }
}
