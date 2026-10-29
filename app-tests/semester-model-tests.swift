import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct SemesterModelTests {
    let springTerm = UUID(uuidString: "5E4F1A00-0000-4000-8000-000000000001")!

    @Test func weekOptionsRunThroughTheTermAndOfferNoneOnlyWithoutADefault() throws {
        let model = SemesterModel(workspace: try fixtureWorkspace(), semesterID: fallTerm)
        let fall = try #require(model.semester)
        // 2026-09-01 is a Tuesday, so week 1 starts on Monday 08-31 and 12-18 falls in week 16.
        let weeks = model.weekOptions(fall, fallback: 8)
        #expect(weeks.count == 16)
        #expect(weeks.first?.1.hasPrefix("1주차 · ") == true)
        let open = model.weekOptions(fall, fallback: nil)
        #expect(open.count == 17 && open[0].0 == nil && open[0].1 == "없음")
        // A default exam week past the term's end still gets a row.
        #expect(model.weekOptions(fall, fallback: 20).count == 20)
    }

    @Test func settingAWeekWritesTheSemester() throws {
        let model = SemesterModel(workspace: try fixtureWorkspace(), semesterID: fallTerm)
        model.setWeek(try #require(model.semester), \.midtermWeek, to: 9)
        #expect(model.semester?.midtermWeek == 9)
        model.setWeek(try #require(model.semester), \.finalWeek, to: nil)
        #expect(model.semester?.finalWeek == nil && model.semester?.midtermWeek == 9)
    }

    @Test func examsAreListedSoonestFirst() throws {
        let workspace = try fixtureWorkspace()
        let model = SemesterModel(workspace: workspace, semesterID: fallTerm)
        let later = Date(timeIntervalSince1970: 1_800_000_000)
        workspace.run(ExamAdd(course: graphTheory, title: "기말", start: later))
        workspace.run(ExamAdd(course: graphTheory, title: "중간", start: later.addingTimeInterval(-86_400 * 30)))
        workspace.run(ExamAdd(course: graphTheory, title: "날짜 없음"))
        let fall = try #require(model.semester)
        #expect(model.exams(of: model.courses(in: fall)).map(\.exam.title) == ["중간", "기말"])
    }

    @Test func aPastTermShowsItsDatesWithoutTheCurrentWeek() throws {
        let model = SemesterModel(workspace: try fixtureWorkspace(), semesterID: springTerm)
        let spring = try #require(model.semester)
        #expect(!model.isCurrent(spring) && model.markedWeekday(spring) == nil)
        #expect(!model.subtitle(spring).contains("지금"))
        #expect(model.stats(spring).map(\.value).first == "1개")
    }
}

@MainActor
struct AddSheetModelTests {
    @Test func aNewSemesterStartsAfterTheNewestAndRefusesADuplicate() throws {
        let model = AddSemesterModel(workspace: try fixtureWorkspace())
        #expect((model.year, model.term) == (2026, .winter))
        #expect(!model.exists && model.note?.hasPrefix("폴더 ") == true)
        model.term = .fall
        #expect(model.exists && model.note == "이미 있는 학기입니다")
    }

    @Test func aCourseNeedsACodeBeforeItCanBeAdded() throws {
        let workspace = try fixtureWorkspace()
        let fall = try #require(workspace.transcript.semesters.first { $0.id == fallTerm })
        let model = AddCourseModel(workspace: workspace, semester: fall)
        model.title = "알고리즘"
        model.number = "3001"
        #expect(model.disabled)
        #expect(model.add() == nil)
    }
}
