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
        let plan = CleanupPlanner.plan(try gist.readTree())
        let targets = Dictionary(uniqueKeysWithValues: plan.moves.map { ($0.from, $0.to) })
        let ma = "2026-1/MA2001 선형대수학", ec = "2026-3/EC4207 그래프 이론", robot = "2026-3/EC4321 로봇공학"

        #expect(Set(plan.skipped) == ["GIST OTP", "과대표"])
        #expect(targets["2026-1/학사/2026-1 시험시간표.pdf"] == "2026-1/_Admin/2026-1 시험시간표.pdf")
        #expect(targets["2026-1/수강신청 확인서.pdf"] == "2026-1/_Admin/수강신청 확인서.pdf")
        #expect(targets["\(ma)/강의자료/week1.pdf"] == "\(ma)/Lectures/01_week1.pdf")
        #expect(targets["\(ma)/노트/1주차.md"] == "\(ma)/Notes/1주차.md")
        #expect(targets["\(ma)/노트/1주차 필기.pdf"] == "\(ma)/Archive/1주차 필기.pdf")
        #expect(targets["\(ma)/족보/2024 중간.pdf"] == "\(ma)/Exams/Past/2024 Midterm.pdf")
        #expect(targets["\(ec)/Homeworks/26h3.pdf"] == "\(ec)/Assignments/HW03/26h3.pdf")
        #expect(targets["\(ec)/Homeworks/HW3-5070류현승.pdf"] == "\(ec)/Assignments/HW03/HW3-5070류현승.pdf")
        #expect(targets["\(ec)/족보 (소순범)/2024 Midterm.pdf"] == "\(ec)/Exams/Past/2024 Midterm (소순범).pdf")
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
        let before = try gist.readTree()
        let plan = CleanupPlanner.plan(before)

        let batch = try MoveJournal.apply(plan.moves, in: gist.url, device: device, now: now)
        let remaining = try gist.layoutIssues()
        #expect(Set(remaining) == Set(plan.skipped.map { LayoutIssue(.unexpectedRootItem, $0) }))

        try MoveJournal.undo(batch: batch, in: gist.url, device: device, now: now)
        var restored = try gist.readTree()
        restored.content = .folder(restored.children.filter { $0.name != StandardLayout.metadataFolder })  // the journal itself stays
        #expect(restored == before)
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
