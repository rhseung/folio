import FolioActions
import FolioDomain
import Foundation
import Testing

@testable import Folio

@MainActor
struct UnitsModelTests {
    func file(_ workspace: Workspace) throws -> CourseFile { try #require(workspace.course(graphTheory)).file }

    @Test func addClearsTheFieldAndRemoveClosesTheOpenUnit() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        #expect(!model.canAdd)
        model.newTitle = "매칭"
        model.add()
        #expect(model.newTitle.isEmpty)
        let unit = try #require(try file(workspace).units.first)
        #expect(unit.title == "매칭")

        model.openUnit = unit.id
        model.remove(unit)
        let pending = try #require(model.pending)
        #expect(
            pending.question == workspace.confirmation(UnitRemove(course: graphTheory, unit: unit.id)) && pending.question.contains("'매칭'"))
        #expect(pending.refusal == nil)
        #expect(try file(workspace).units.count == 1)
        pending.perform()
        #expect(try file(workspace).units.isEmpty && model.openUnit == nil)
    }

    @Test func sessionsLineNamesThreeThenCountsTheRest() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        let unitId = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        #expect(model.sessionsLine(try #require(try file(workspace).units.first), in: try file(workspace)) == "회차 없음")
        let ids = try (1...4).map { day in
            try #require(
                workspace.run(SessionAdd(course: graphTheory, date: Calendar.current.date(byAdding: .day, value: -day * 7, to: .now)!))?
                    .made)
        }
        workspace.run(UnitLink(course: graphTheory, unit: unitId, sessions: ids))
        let f = try file(workspace)
        let unit = try #require(f.units.first)
        let names = model.sessions(of: unit, in: f).map { f.day(of: $0, calendar: workspace.calendar) }
        #expect(model.sessionsLine(unit, in: f) == "\(names.prefix(3).joined(separator: ", ")) 외 1")
    }

    @Test func linkMenuLeavesOutCancelledClassesUnlessLinked() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        let unitId = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let day = { (d: Int) in Calendar.current.date(byAdding: .day, value: -d, to: .now)! }
        let held = try #require(workspace.run(SessionAdd(course: graphTheory, date: day(2)))?.made)
        let cancelled = try #require(workspace.run(SessionAdd(course: graphTheory, date: day(1), kind: .cancelled))?.made)
        func menu() throws -> [UUID] { model.linkMenu(try #require(try file(workspace).units.first), in: try file(workspace)).map(\.id) }
        #expect(try menu() == [held])
        workspace.run(UnitLink(course: graphTheory, unit: unitId, sessions: [cancelled]))
        #expect(try menu() == [cancelled, held])
    }

    @Test func subtitleCountsUnitsDoneAndUnlinkedClasses() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        workspace.run(UnitAdd(course: graphTheory, title: "매칭"))
        workspace.run(SessionAdd(course: graphTheory, date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!))
        #expect(model.subtitle(try file(workspace)) == "단원 1개 · 다 함 0 · 단원 없는 회차 1")
        let unit = try #require(try file(workspace).units.first)
        model.toggleDone(unit)
        #expect(model.subtitle(try file(workspace)).hasPrefix("단원 1개 · 다 함 1"))
    }

    @Test func aClassNoteLeavesTheUnitWithItsClass() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        let unitId = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let session = try #require(
            workspace.run(SessionAdd(course: graphTheory, date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!))?.made)
        workspace.run(UnitLink(course: graphTheory, unit: unitId, sessions: [session]))
        let note = try #require(workspace.run(SessionNote(course: graphTheory, session: session, kind: .review))?.made)
        model.loadNotes(try #require(try file(workspace).units.first))
        #expect(model.notes.map(\.meta.id) == [note])

        workspace.run(UnitLink(course: graphTheory, unit: unitId, sessions: [session], linked: false))
        model.loadNotes(try #require(try file(workspace).units.first))
        #expect(model.notes.isEmpty)
    }

    @Test func thePlanShowsItsFirstDaysAndFoldsTheRest() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        let start = Date.now.addingTimeInterval(20 * 86_400)
        let examId = try #require(workspace.run(ExamAdd(course: graphTheory, title: "기말고사", start: start))?.made)
        for d in [0, 1, 2, 5, 9] {
            workspace.run(ExamPlanAdd(course: graphTheory, exam: examId, title: "할 일 \(d)", day: workspace.today.adding(days: d)))
        }
        let exam = try #require(try file(workspace).exams.first { $0.id == examId })
        let all = exam.plan.filter { !$0.isRemoved }.count
        let shownDays = workspace.settings.study.planShownDays
        let folded = model.planRows(exam)
        #expect(folded.rows.allSatisfy { workspace.today.days(until: $0.item.day) < shownDays })
        #expect(folded.rows.count + folded.folded == all && folded.folded > 0)
        #expect(model.planToggleLabel(folded: folded.folded) == "\(folded.folded)개 더 보기")
        model.planOpen = true
        #expect(model.planRows(exam).rows.count == all && model.planToggleLabel(folded: folded.folded) == "접기")
    }

    @Test func otherUnitsAreGroupedUnderThePastExamThenUntaught() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        let units = try ["매칭", "연결도", "채색"].map { try #require(workspace.run(UnitAdd(course: graphTheory, title: $0))?.made) }
        let day = { (d: Int) in Date.now.addingTimeInterval(Double(d) * 86_400) }
        workspace.run(ExamAdd(course: graphTheory, title: "중간고사", start: day(-30), scope: [units[0]]))
        workspace.run(ExamAdd(course: graphTheory, title: "기말고사", start: day(20), scope: [units[1]]))
        let exam = try #require(model.nextExam)
        let sections = model.otherSections(exam, rest: model.rows(in: exam).rest)
        #expect(sections.map(\.title) == ["중간고사 범위", "아직 안 배운 단원"])
        #expect(sections.map { $0.rows.map(\.unit.id) } == [[units[0]], [units[2]]])
        #expect(model.otherSummary(sections) == "중간고사 범위 1 · 아직 안 배운 단원 1")
    }
}
