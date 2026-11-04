import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct CleanupTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 3_000_000)

    @Test func legacyPlanMatchesSpecTable() throws {
        let gist = GISTStore(url: try Fixture.legacy.copyToTemp())
        let plan = try gist.cleanupPlan()
        let targets = Dictionary(uniqueKeysWithValues: plan.moves.map { ($0.from, $0.to) })
        let move = Dictionary(uniqueKeysWithValues: plan.moves.map { ($0.from, $0) })
        let ma = "2026-1/MA2001 선형대수학", ec = "2026-3/EC4207 그래프 이론", robot = "2026-3/EC4321 로봇공학"
        let chem = "2026-3/GS1211 일반화학실험", la = "2026-3/GS2004 선형대수학"

        #expect(Set(plan.skipped) == ["GIST OTP", "과대표"])
        #expect(targets["2026-1/학사/2026-1 시험시간표.pdf"] == "2026-1/_Admin/2026-1 시험시간표.pdf")
        #expect(targets["2026-1/수강신청 확인서.pdf"] == "2026-1/_Admin/수강신청 확인서.pdf")
        #expect(targets["\(ma)/강의자료/week1.pdf"] == "\(ma)/Lectures/01_week1.pdf")
        #expect(targets["\(ma)/노트/1주차.md"] == "\(ma)/Notes/1주차.md")
        #expect(targets["\(ma)/노트/1주차 필기.pdf"] == "\(ma)/Archive/1주차 필기.pdf")
        #expect(move["\(ma)/족보/2024 중간.pdf"].map { ($0.to, $0.kind) }! == ("\(ma)/Inherited/2024 중간.pdf", .pastExam))
        #expect(targets["\(ec)/Homeworks/26h3.pdf"] == "\(ec)/Assignments/HW03/26h3.pdf")
        #expect(targets["\(ec)/Homeworks/HW3-5070류현승.pdf"] == "\(ec)/Assignments/HW03/HW3-5070류현승.pdf")
        #expect(targets["\(ec)/족보 (소순범)/2024 Midterm.pdf"] == "\(ec)/Inherited/소순범/2024 Midterm.pdf")
        #expect(move["\(ec)/Exam Review/Problems.tex"].map { ($0.to, $0.exam, $0.review) }! == ("\(ec)/Study/Problems.tex", "Midterm", nil))
        #expect(move["\(ec)/Exams/Quiz3/Quiz3 대비 정리.pdf"].map { ($0.to, $0.exam, $0.review) }!
            == ("\(ec)/Study/Quiz3 대비 정리.pdf", "Quiz3", .guessedOrigin))
        #expect(targets["\(ec)/Notes/Exports/Matchings.pdf"] == "\(ec)/Study/Matchings.pdf")
        #expect(plan.removals == ["\(ec)/Exams/Quiz1"])
        #expect(move["\(chem)/Exams/Past/관훈 선배 리포트"].map { ($0.to, $0.kind) }! == ("\(chem)/Inherited/관훈 선배 리포트", nil))
        #expect(move["\(chem)/Exams/Past/mid-sol.pdf"].map { ($0.to, $0.kind) }! == ("\(chem)/Inherited/mid-sol.pdf", .pastExam))
        // The journal says these came from `Exam Review`; the image beside them is only a suggestion.
        #expect(move["\(la)/Exercises/Proofs.pdf"].map { ($0.to, $0.exam, $0.review) }! == ("\(la)/Study/Proofs.pdf", "Midterm", nil))
        #expect(move["\(la)/Exercises/exercise 1.png"].map { ($0.to, $0.review) }! == ("\(la)/Study/exercise 1.png", .guessedOrigin))
        #expect(targets["\(ec)/Midterm Seating.pdf"] == "\(ec)/Exams/Midterm/Seating.pdf")
        // Without the lab schedule the week is unknown, so the manual takes the next free week and is flagged.
        #expect(targets["\(robot)/Manuals/Lab1 Manual.pdf"]?.hasPrefix("\(robot)/Lectures/") == true)
        #expect(plan.moves.first { $0.from == "\(robot)/Manuals/Lab1 Manual.pdf" }?.review == .unknownWeek)
        #expect(targets["\(robot)/Reports/Lab1 Report.pdf"] == "\(robot)/Assignments/Lab01/Lab1 Report.pdf")
        // A code project keeps its name; only its parent changes.
        #expect(targets["\(robot)/Assignments/robot"] == "\(robot)/Assignments/Project01/robot")
    }

    @Test func applyReachesStandardLayoutAndUndoRestoresIt() throws {
        let gist = GISTStore(url: try Fixture.legacy.copyToTemp())
        // The journal itself changes, so trees are compared without it.
        func tree() throws -> FolderTree {
            var tree = try gist.readTree()
            tree.content = .folder(tree.children.filter { $0.name != StandardLayout.metadataFolder })
            return tree
        }
        let before = try tree()
        let plan = try gist.cleanupPlan()

        let batch = try MoveJournal.apply(plan.moves, removing: plan.removals, in: gist.url, device: device, now: now)
        let remaining = try gist.layoutIssues()
        #expect(Set(remaining) == Set(plan.skipped.map { LayoutIssue(.unexpectedRootItem, $0) }))

        try MoveJournal.undo(batch: batch, in: gist.url, device: device, now: now)
        #expect(try tree() == before)
    }

    @Test func undoKeepsFilesAddedToAFolderTheBatchMade() throws {
        let gist = GISTStore(url: try Fixture.legacy.copyToTemp())
        let move = PlannedMove(from: "2026-1/수강신청 확인서.pdf", to: "2026-1/_Admin/수강신청 확인서.pdf")
        let batch = try MoveJournal.apply([move], in: gist.url, device: device, now: now)
        let added = gist.url.appending(path: "2026-1/_Admin/나중에 넣은 파일.pdf")
        try Data("new".utf8).write(to: added)

        try MoveJournal.undo(batch: batch, in: gist.url, device: device, now: now)
        #expect(FileManager.default.fileExists(atPath: added.path))
        #expect(FileManager.default.fileExists(atPath: gist.url.appending(path: move.from).path))
    }

    @Test func stalePlanMovesNothing() throws {
        let gist = GISTStore(url: try Fixture.legacy.copyToTemp())
        let before = try gist.readTree()
        var moves = CleanupPlanner.plan(before).moves
        moves.append(PlannedMove(from: "2026-1/없는 파일.pdf", to: "2026-1/_Admin/없는 파일.pdf"))

        #expect(throws: MoveJournal.Failure.sourceMissing("2026-1/없는 파일.pdf")) {
            try MoveJournal.apply(moves, in: gist.url, device: device, now: now)
        }
        #expect(try gist.readTree() == before)
    }

    @Test func skipLeavesUndecidedFoldersAlone() throws {
        let gist = GISTStore(url: try Fixture.legacy.copyToTemp())
        let plan = CleanupPlanner.plan(try gist.readTree(), skip: ["2026-1"])
        #expect(plan.skipped.contains("2026-1"))
        #expect(!plan.moves.contains { $0.from.hasPrefix("2026-1/") })
    }

    @Test func planFileRoundTrips() throws {
        let gist = GISTStore(url: try Fixture.legacy.copyToTemp())
        let plan = CleanupPlanner.plan(try gist.readTree())
        let url = gist.url.deletingLastPathComponent().appending(path: "plan.json")
        try StoredDocument(new: plan).write(to: url)
        #expect(try StoredDocument<CleanupPlan>.read(from: url).model == plan)
    }
}
