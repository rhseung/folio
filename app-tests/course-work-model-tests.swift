import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

/// 선형대수학 in the standard fixture: no exams, assignments or tracked files, one rough note.
private let linearAlgebra = UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!

@MainActor
private func fixtureCourse() throws -> (Workspace, LoadedCourse) {
    let workspace = try fixtureWorkspace()
    return (workspace, try #require(workspace.course(linearAlgebra)))
}

@MainActor
struct ExamsModelTests {
    @Test func subtitleCountsComingAndPast() throws {
        let (workspace, course) = try fixtureCourse()
        let model = ExamsModel(workspace: workspace, course: course)
        #expect(model.subtitle(coming: 0, past: 0) == "등록한 시험이 없습니다")
        #expect(model.subtitle(coming: 0, past: 2) == "예정된 시험 없음 · 지난 시험 2개")
        #expect(model.subtitle(coming: 1, past: 0) == "예정 1개")
    }

    @Test func editorNamesQuizzesByFolderAndSplitsComingFromPast() throws {
        let (workspace, course) = try fixtureCourse()
        let now = Date.now
        for days in [-20, -10, 10] {
            let editor = ExamEditorModel(workspace: workspace, course: course,
                                         exam: Exam(device: workspace.device, at: now, kind: .quiz, title: "", start: now + Double(days) * 86_400))
            #expect(editor.isNew && editor.title == "시험 추가" && editor.confirm == "추가")
            #expect(editor.apply())
            #expect(!editor.isNew && editor.title == "\(editor.draft.title) 편집")
        }
        let model = ExamsModel(workspace: workspace, course: course)
        let (coming, past) = model.exams(now: now)
        #expect(coming.map(\.title) == ["Quiz3"])
        // Past exams read from the latest back.
        #expect(past.map(\.title) == ["Quiz2", "Quiz1"])
        // No scope, place, files or plan: only the kind is left to say.
        #expect(model.pastFacts(past[0]) == ExamKind.quiz.label)
    }

    @Test func movingTheStartCarriesTheEnd() throws {
        let (workspace, course) = try fixtureCourse()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let editor = ExamEditorModel(workspace: workspace, course: course,
                                     exam: Exam(device: workspace.device, at: start, kind: .midterm, title: "", start: start, end: start + 7200))
        #expect(editor.note == "시험 폴더 Exams/Midterm도 만듭니다")
        editor.setStart(start + 86_400)
        #expect(editor.draft.end == start + 86_400 + 7200)
        editor.draft.end = start
        #expect(editor.endsBeforeStart && editor.disabled)
    }

    @Test func scopeLineNamesUnitsOrText() throws {
        let (workspace, course) = try fixtureCourse()
        let model = ExamsModel(workspace: workspace, course: course)
        var exam = Exam(device: workspace.device, at: .now, kind: .midterm, title: "Midterm")
        #expect(model.scopeLine(exam, units: 0) == "범위 단원을 고르지 않았습니다")
        exam.scopeText = "3장까지"
        #expect(model.scopeLine(exam, units: 0) == "3장까지")
        #expect(model.scopeLine(exam, units: 2) == "단원 2개 · 3장까지")
        #expect(model.planLine([]) == "날짜별 할 일을 넣으면 그날 오늘 화면에도 나옵니다")
    }
}

@MainActor
struct AssignmentsModelTests {
    @Test func groupsAndSubtitleFollowStatusAndDeadline() throws {
        let (workspace, course) = try fixtureCourse()
        let now = Date.now
        workspace.run(AssignmentAdd(course: linearAlgebra, title: "HW 1", due: now - 3600))
        workspace.run(AssignmentAdd(course: linearAlgebra, title: "HW 2", due: now + 5 * 86_400))
        workspace.run(AssignmentAdd(course: linearAlgebra, title: "HW 3"))
        let model = AssignmentsModel(workspace: workspace, course: course)
        #expect(model.subtitle == "과제 3개 · 남은 과제 3개 · 마감 없음 1개")
        let groups = model.groups(now: now)
        #expect(groups.map(\.group) == [.overdue, .open])
        #expect(groups[1].items.map(\.title) == ["HW 2", "HW 3"])
        #expect(groups.map(\.group.label) == ["마감 지남", "진행 중"])

        let late = groups[0].items[0]
        #expect(model.dueChip(late, now: now)?.text == "방금 지남")
        let chip = try #require(model.dueChip(groups[1].items[0], now: now))
        #expect(chip.text == "D-5" && chip.tone == .plain)
        #expect(model.due(groups[1].items[1]).date == "마감 없음")
        model.setStatus(late, .submitted)
        #expect(model.groups(now: now).map(\.group) == [.open, .submitted])
        #expect(model.dueChip(try #require(model.course.file.assignments.first { $0.title == "HW 1" }), now: now) == nil)
    }

    @Test func sheetOffersGroupsAsATreeAndFillsTheLastMax() throws {
        let (workspace, course) = try fixtureCourse()
        let a = try #require(workspace.run(ComponentAdd(course: linearAlgebra, name: "Lab 1", weight: 5, group: "Lab"))?.made)
        workspace.run(ComponentAdd(course: linearAlgebra, name: "Lab 2", weight: 5, group: "Lab"))
        workspace.run(ScoreAdd(course: linearAlgebra, component: a, score: 8, max: 20))
        let id = try #require(workspace.run(AssignmentAdd(course: linearAlgebra, title: "Lab 1"))?.made)
        let model = AssignmentSheetModel(workspace: workspace, course: course, assignment: try #require(workspace.course(linearAlgebra)?.file.assignments.first { $0.id == id }))
        model.load()
        #expect(model.targetOptions.map(\.title) == ["없음", "Lab 전체", "Lab 1", "Lab 2"])
        model.pick(.group("Lab"))
        #expect(model.targetComponents.count == 2)
        #expect(model.maxes[a] == "20")
        model.scores[a] = "x"
        #expect(model.invalid)
        model.scores[a] = "9"
        #expect(!model.invalid)
        #expect(model.titleDetail == nil)
    }
}

@MainActor
struct MaterialsModelTests {
    @Test func importPlacesGroupByKindAndPickTheNewest() throws {
        let (workspace, course) = try fixtureCourse()
        let model = ImportPlaceModel(workspace: workspace, course: course, files: [URL(filePath: "/tmp/a.pdf"), URL(filePath: "/tmp/b.pdf")],
                                     places: MaterialIntake.places(assignmentFolders: ["HW01", "HW02"]))
        #expect(model.title == "파일 2개 넣기")
        let assignments = try #require(model.kinds.first { $0.places.contains("Assignments/HW01") })
        #expect(assignments.places == ["Assignments/HW01", "Assignments/HW02"] && assignments.perItem)
        #expect(model.shown(assignments) == "Assignments/…")
        model.pick(assignments.places)
        #expect(model.place == "Assignments/HW02")
        #expect(model.shown(assignments) == "Assignments/HW02")
        #expect(model.kinds.first?.isLecture == true)
    }

    @Test func trackingFillsTheTreeAndFoldersOpenOnToggle() throws {
        let (workspace, course) = try fixtureCourse()
        workspace.run(MaterialTrack(course: linearAlgebra))
        let model = MaterialsModel(workspace: workspace, course: course)
        #expect(model.subtitle.hasPrefix("파일 \(model.materials.count)개"))
        let lectures = try #require(model.sections().first { $0.role == .lecture })
        #expect(lectures.count == 3)
        #expect(model.renameMessage(lectures.rows.compactMap { if case .file(let m, _, _) = $0 { m } else { nil } }[0]) == "확장자 .pdf는 그대로 둡니다. 바꾼 이름은 되돌릴 수 있게 기록합니다.")
    }
}

@MainActor
struct NotesModelTests {
    @Test func listSectionsByKindAndCreatesIntoTheFilter() throws {
        let (workspace, course) = try fixtureCourse()
        let model = NoteListModel(workspace: workspace, course: course)
        model.reload()
        #expect(model.parts.map(\.title) == ["수업 노트"])
        #expect(model.parts[0].rows[0].detail == "러프 · 회차 없음")

        model.filter = .topic
        #expect(model.emptyLine == "단원 정리 노트가 없습니다")
        #expect(model.titlePrompt == "새 단원 정리 노트 제목")
        model.newTitle = "  행렬식  "
        let id = try #require(model.create())
        #expect(model.newTitle.isEmpty && !model.adding)
        #expect(model.shown.map(\.title) == ["행렬식"])
        #expect(model.shown[0].meta.id == id)
        #expect(model.parts.first?.rows.first?.detail == "단원 없음")

        model.filter = nil
        #expect(model.parts.map(\.title) == ["수업 노트", "단원 정리"])
        model.delete(model.shown.first { $0.meta.id == id }!)
        #expect(model.parts.map(\.title) == ["수업 노트"])
    }

    @Test func editorNamesItsLinkAndFindsNotesByTitle() throws {
        let (workspace, course) = try fixtureCourse()
        let notes = NotesModel(workspace: workspace, course: course)
        let id = try #require(notes.noteId(titled: "1주차-1"))
        #expect(notes.noteId(titled: "1주차-1".uppercased()) == id)
        let editor = NoteEditorModel(workspace: workspace, course: course, note: try #require(notes.note(id)))
        editor.load()
        #expect(editor.currentLink == "러프 노트 · 회차 없음")
        #expect(!editor.dirty)
        editor.append("끝")
        #expect(editor.dirty && editor.body.hasSuffix("\n\n끝\n"))
        editor.relink(.free)
        #expect(editor.currentLink == "자유 노트" && !editor.dirty)
        #expect(NoteEditorModel.markdown(for: URL(filePath: "/x/a b.png"), path: "assets/a b.png") == "![a b](assets/a%20b.png)")
    }
}
