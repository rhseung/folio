import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import Folio

@MainActor
struct SemesterModelTests {
    let springTerm = UUID(uuidString: "5E4F1A00-0000-4000-8000-000000000001")!

    @Test func weekOptionsRunThroughTheTermAndOfferNoneOnlyWithoutADefault() throws {
        let model = SemesterModel(workspace: try fixtureWorkspace(), semesterID: fallTerm)
        let fall = try #require(model.semester)
        // 2026-09-01은 화요일이므로 1주차는 08-31 월요일에 시작하고, 12-18은 16주차에 든다.
        let weeks = model.weekOptions(fall, fallback: 8)
        #expect(weeks.count == 16)
        #expect(weeks.first?.1.hasPrefix("1주차 · ") == true)
        let open = model.weekOptions(fall, fallback: nil)
        #expect(open.count == 17 && open[0].0 == nil && open[0].1 == "없음")
        #expect(model.weekOptions(fall, fallback: 20).count == 20)
    }

    @Test func aFinishedSemesterOffersToTrimOnlyTranscribedAudio() async throws {
        let workspace = try fixtureWorkspace()
        let linearAlgebra = UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!
        let ctx = ActionContext(gist: try #require(workspace.gist), device: workspace.device, now: workspace.now)
        let store = try ctx.store(linearAlgebra)
        let heard = Recording(device: workspace.device, at: .now, sessionId: nil, file: "Recordings/a.m4a", duration: 60)
        let silent = Recording(device: workspace.device, at: .now, sessionId: nil, file: "Recordings/b.m4a", duration: 60)
        try FileManager.default.createDirectory(at: store.recordingsURL, withIntermediateDirectories: true)
        for r in [heard, silent] { try Data("audio".utf8).write(to: store.fileURL(r.file)) }
        try store.saveTranscript(LectureTranscript(locale: "ko-KR", lines: [.init(start: 0, end: 5, text: "행렬")]), of: heard)
        try ctx.edit(linearAlgebra) { $0.recordings = [heard, silent] }
        workspace.reload()

        let model = SemesterModel(workspace: workspace, semesterID: springTerm)
        await model.refreshAudio()
        let audio = try #require(model.audio)
        #expect(audio.items.map(\.count) == [1] && audio.kept == 1)
        await model.trim()
        #expect(model.audio == nil)
        #expect(workspace.course(linearAlgebra)?.file.recordings.filter(\.hasAudio).map(\.id) == [silent.id])
    }

    @Test func aSemesterUnderWayOffersNothing() async throws {
        let model = SemesterModel(workspace: try fixtureWorkspace(), semesterID: fallTerm)
        await model.refreshAudio()
        #expect(model.audio == nil)
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

    @Test func aCreditedTermsSourceRenamesItsFolder() throws {
        let workspace = try fixtureWorkspace()
        let model = SemesterModel(workspace: workspace, semesterID: creditedTerm)
        model.loadSource()
        #expect(model.source == "영재고 AP" && !model.canSaveSource)
        model.source = "  "
        #expect(!model.canSaveSource)

        model.source = "군 복무"
        #expect(model.sourceFolder == "_Credited/군 복무" && model.canSaveSource)
        #expect(model.sourceConfirmation().contains("군 복무"))
        model.saveSource()
        #expect(model.semester?.source == "군 복무" && model.source == "군 복무")
        let root = try #require(workspace.gist).url
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "_Credited/군 복무/GS1101 일반물리학 및 연습 I/.folio/course.json").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "_Credited/영재고 AP").path))
        #expect(model.courses(in: try #require(model.semester)).count == 1)
    }

    @Test func aSourceWithASlashIsRefused() throws {
        let model = SemesterModel(workspace: try fixtureWorkspace(), semesterID: creditedTerm)
        model.source = "영재고/AP"
        #expect(model.sourceFolder == nil && !model.canSaveSource && model.sourceRefusal != nil)
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
