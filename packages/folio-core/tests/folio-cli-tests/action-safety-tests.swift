@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

/// Rules the app keeps by hiding controls, held by the actions so `folio` and `folio run` can't break them either.
struct ActionSafetyTests {
    let h = Harness()
    typealias G = GradesSetupTests

    func settled(_ lines: [[String]], gist: URL) {
        for line in lines {
            let r = h.cli(line, gist: gist)
            #expect(r.code == 0, "\(line): \(r.err)")
        }
    }

    @Test func singleComponentTakesOneScore() throws {
        let gist = try Harness.fixtureCopy()
        settled([["component", "add", "EC4207", "중간고사", "--weight", "30", "--aggregation", "single"],
                 ["score", "add", "EC4207", "--component", "중간고사", "--score", "8.5", "--max", "30"]], gist: gist)
        let r = h.cli(["score", "add", "EC4207", "--component", "중간고사", "--title", "Midterm", "--score", "11", "--max", "30"], gist: gist)
        #expect(r.code == Exit.rule.rawValue)
        #expect(r.err.contains("단일 성적 항목 '중간고사'"))
    }

    @Test func untitledScoreGoesByItsComponent() throws {
        let gist = try Harness.fixtureCopy()
        settled([["component", "add", "EC4207", "중간고사", "--weight", "30", "--aggregation", "single"]], gist: gist)
        let add = h.cli(["score", "add", "EC4207", "--component", "중간고사", "--score", "20", "--max", "30"], gist: gist)
        #expect(add.out.contains("점수 '중간고사'"), "\(add.out)")
        let rm = h.cli(["score", "rm", "EC4207/중간고사", "--yes"], gist: gist)
        #expect(rm.code == 0, "\(rm.err)")
    }

    @Test func aggregationCountIsPositive() throws {
        let gist = try Harness.fixtureCopy()
        let r = h.cli(["component", "add", "EC4207", "퀴즈", "--weight", "20", "--aggregation", "dropLowest:-1"], gist: gist)
        #expect(r.code == Exit.rule.rawValue)
    }

    @Test func scoreMustPointIntoItsCourse() throws {
        let gist = try Harness.fixtureCopy()
        settled([G.addComponent], gist: gist)
        let input = #"{"course":"EC4207","component":"과제","exam":"\#(UUID())","title":"HW1","score":9,"max":10}"#
        let r = h.cli(["run", "score", "add", "--input", input], gist: gist)
        #expect(r.code == Exit.rule.rawValue)
        #expect(r.err.contains("시험이 이 과목에 없습니다"))
    }

    @Test func runAsksBeforeRemoving() throws {
        let gist = try Harness.fixtureCopy()
        settled([G.addComponent, G.addScore], gist: gist)
        let input = #"{"course":"EC4207","score":"\#(G.score)"}"#
        #expect(h.cli(["run", "score", "rm", "--input", input], gist: gist).code == Exit.needsConfirmation.rawValue)
        #expect(h.cli(["run", "score", "rm", "--input", input, "--yes"], gist: gist).code == 0)
    }

    @Test func runLaysWholeFileInputOverTheFile() throws {
        let gist = try Harness.fixtureCopy()
        settled([["settings", "set", "dayBoundaryMinutes", "300"]], gist: gist)
        let settings = GISTStore(url: gist).settingsURL
        let before = try Data(contentsOf: settings)
        #expect(h.cli(["run", "settings", "set", "--input", #"{"settings":{}}"#, "--yes"], gist: gist).code == 0)
        #expect(try Data(contentsOf: settings) == before)
    }

    @Test func catalogKeepsRowsInUse() throws {
        let gist = try Harness.fixtureCopy()
        settled([["catalog", "set", "--file", try GradesSetupTests().catalogFile()],
                 ["course", "add", "EC", "4208-01", "네트워크", "--semester", "2026-3"]], gist: gist)
        let r = h.cli(["run", "catalog", "set", "--input", #"{"catalog":{"codes":[]}}"#, "--yes"], gist: gist)
        #expect(r.code == Exit.rule.rawValue)
        #expect(r.err.contains("과목 '네트워크'의 강의 코드가 catalog.json에 없습니다"))
    }

    @Test func courseIdIsNotReused() throws {
        let gist = try Harness.fixtureCopy()
        settled([["catalog", "set", "--file", try GradesSetupTests().catalogFile()]], gist: gist)
        let r = h.cli(["course", "add", "EC", "4208-01", "네트워크", "--semester", "2026-3", "--id", Harness.graphTheory.uuidString], gist: gist)
        #expect(r.code == Exit.rule.rawValue)
    }

    @Test func movesStayInsideTheGISTFolder() throws {
        let gist = try Harness.fixtureCopy()
        let file = gist.appending(path: "a.txt")
        try Data("x".utf8).write(to: file)
        #expect(throws: MoveJournal.Failure.outsideGIST("../a.txt")) {
            try MoveJournal.apply([PlannedMove(from: "a.txt", to: "../a.txt")], in: gist, device: h.device, now: h.now)
        }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func cancellingASessionDropsItsAttendance() throws {
        let gist = try Harness.fixtureCopy()
        settled([["session", "add", "EC4207", "--date", "2026-10-20 10:30"],
                 ["attendance", "set", "EC4207/8주차-1", "absent"],
                 ["session", "set", "EC4207/8주차-1", "--cancelled", "true"]], gist: gist)
        let file = try GISTStore(url: gist).courseStores().map { try $0.load().model }.first { $0.course.id == Harness.graphTheory }!
        #expect(file.attendance.isEmpty)
        let r = h.cli(["attendance", "set", "EC4207/8주차-1", "absent"], gist: gist)
        #expect(r.code == Exit.rule.rawValue)
        #expect(r.err.contains("휴강한 회차"))
    }

    @Test func examEndsAfterItStarts() throws {
        let gist = try Harness.fixtureCopy()
        let r = h.cli(["exam", "add", "EC4207", "중간", "--start", "2026-11-02 10:00", "--end", "2026-11-02 10:00"], gist: gist)
        #expect(r.code == Exit.rule.rawValue)
        #expect(h.cli(["exam", "add", "EC4207", "", "--start", "2026-11-02 10:00"], gist: gist).code == Exit.rule.rawValue)
    }

    @Test func settingsStayInRange() throws {
        let gist = try Harness.fixtureCopy()
        let r = h.cli(["settings", "set", "dayBoundaryMinutes", "2000"], gist: gist)
        #expect(r.code == Exit.rule.rawValue)
        #expect(r.err.contains("하루 경계"))
    }

    @Test func planCheckNeedsTheItem() throws {
        let gist = try Harness.fixtureCopy()
        settled([["exam", "add", "EC4207", "중간"]], gist: gist)
        let input = #"{"course":"EC4207","item":"\#(UUID())","done":true}"#
        #expect(h.cli(["run", "exam", "plan-check", "--input", input], gist: gist).code == Exit.notFound.rawValue)
    }
}
