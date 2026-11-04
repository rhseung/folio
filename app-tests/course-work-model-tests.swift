import FolioActions
import FolioDomain
import FolioMarkdown
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

    @Test func editorNeedsATitleAndSplitsComingFromPast() throws {
        let (workspace, course) = try fixtureCourse()
        let now = Date.now
        for (days, title) in [(-20, "퀴즈 1"), (-10, "퀴즈 2"), (10, "퀴즈 3")] {
            let editor = ExamEditorModel(workspace: workspace, course: course,
                                         exam: Exam(device: workspace.device, at: now, title: "", start: now + Double(days) * 86_400))
            #expect(editor.isNew && editor.title == "시험 추가" && editor.confirm == "추가")
            #expect(editor.disabled && editor.note == nil)
            editor.draft.title = title + " "
            #expect(!editor.disabled)
            #expect(editor.apply())
            #expect(!editor.isNew && editor.title == "\(title) 편집")
        }
        let model = ExamsModel(workspace: workspace, course: course)
        let (coming, past) = model.exams(now: now)
        #expect(coming.map(\.title) == ["퀴즈 3"])
        // Past exams read from the latest back.
        #expect(past.map(\.title) == ["퀴즈 2", "퀴즈 1"])
        #expect(past.map { model.folder(of: $0) } == ["Exams/퀴즈 2", "Exams/퀴즈 1"])
        // No component, scope, place, files or plan: nothing is left to say.
        #expect(model.pastFacts(past[0]).isEmpty)
    }

    @Test func movingTheStartCarriesTheEnd() throws {
        let (workspace, course) = try fixtureCourse()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let editor = ExamEditorModel(workspace: workspace, course: course,
                                     exam: Exam(device: workspace.device, at: start, title: "중간고사", start: start, end: start + 7200))
        #expect(editor.note == "파일을 넣으면 시험 폴더 Exams/중간고사에 둡니다")
        editor.setStart(start + 86_400)
        #expect(editor.draft.end == start + 86_400 + 7200)
        editor.draft.end = start
        #expect(editor.endsBeforeStart && editor.disabled)
    }

    @Test func scopeLineNamesUnitsOrText() throws {
        let (workspace, course) = try fixtureCourse()
        let model = ExamsModel(workspace: workspace, course: course)
        var exam = Exam(device: workspace.device, at: .now, title: "Midterm")
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
        #expect(chip.text == "D-5" && chip.tone == .warning)
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

/// Both pages that take scores save them with the same meaning.
@MainActor
struct ScoreSourceModelTests {
    func setUp() throws -> (Workspace, homework: UUID, lab: UUID, assignment: UUID, exam: UUID) {
        let (workspace, _) = try fixtureCourse()
        let homework = try #require(workspace.run(ComponentAdd(course: linearAlgebra, name: "숙제", weight: 20))?.made)
        let lab = try #require(workspace.run(ComponentAdd(course: linearAlgebra, name: "실험", weight: 20))?.made)
        let assignment = try #require(workspace.run(AssignmentAdd(course: linearAlgebra, title: "HW 3"))?.made)
        workspace.run(AssignmentStatusSet(course: linearAlgebra, assignment: assignment, status: .submitted))
        let exam = try #require(workspace.run(ExamAdd(course: linearAlgebra, title: "쪽지시험", component: lab))?.made)
        return (workspace, homework, lab, assignment, exam)
    }

    func sheet(_ workspace: Workspace, _ assignment: UUID) throws -> AssignmentSheetModel {
        let course = try #require(workspace.course(linearAlgebra))
        let model = AssignmentSheetModel(workspace: workspace, course: course, assignment: try #require(course.file.assignments.first { $0.id == assignment }))
        model.load()
        return model
    }

    @Test func aScoreFromTheGradesPageGoesToItsAssignment() throws {
        let (workspace, homework, _, assignment, exam) = try setUp()
        let course = try #require(workspace.course(linearAlgebra))
        let model = ScoreEntryModel(workspace: workspace, course: course,
                                    entry: ScoreEntry(device: workspace.device, at: .now, componentId: homework, title: "", score: 0, max: 10))
        let options = model.sourceOptions
        #expect(options.map(\.title) == ["없음", "HW 3", "쪽지시험"])
        #expect(options.map(\.section) == [nil, "과제", "시험"])
        model.pick(.assignment(assignment))
        #expect(model.title == "HW 3")
        model.score = "9"
        #expect(model.confirm())

        let file = try #require(workspace.course(linearAlgebra)).file
        #expect(file.scores.first { $0.componentId == homework }?.assignmentId == assignment)
        #expect(file.assignments.first { $0.id == assignment }?.status == .graded)
        // The assignment sheet now shows that score.
        let assignmentSheet = try sheet(workspace, assignment)
        #expect(assignmentSheet.scores[homework] == "9")

        // A second score for HW 3 in 숙제 can't pick it.
        let next = ScoreEntryModel(workspace: workspace, course: try #require(workspace.course(linearAlgebra)),
                                   entry: ScoreEntry(device: workspace.device, at: .now, componentId: homework, title: "", score: 0, max: 10))
        #expect(next.sourceOptions.first { $0.id == .assignment(assignment) }?.disabled == true)
        #expect(next.sourceOptions.first { $0.id == .exam(exam) }?.disabled == false)
    }

    @Test func savingTheSheetKeepsWhatTheGradesPageChanged() throws {
        let (workspace, homework, lab, assignment, _) = try setUp()
        workspace.run(AssignmentSave(course: linearAlgebra, assignment: assignment, title: "HW 3", due: nil, status: .submitted, repeats: nil,
                                     componentId: homework, componentGroup: nil, memo: "", components: [homework],
                                     scores: [.init(component: homework, score: 9, max: 10)]))
        let entry = try #require(workspace.course(linearAlgebra)?.file.scores.first { $0.assignmentId == assignment })

        // On the grades page: renamed, and moved to 실험.
        let edit = ScoreEntryModel(workspace: workspace, course: try #require(workspace.course(linearAlgebra)), entry: entry)
        edit.componentId = lab
        edit.title = "HW 3 재채점"
        #expect(edit.confirm())

        // In the assignment sheet: only the due date changes.
        let model = try sheet(workspace, assignment)
        model.hasDue = true
        #expect(model.apply())
        let kept = try #require(workspace.course(linearAlgebra)?.file.scores.first { $0.id == entry.id })
        #expect(kept.componentId == lab && kept.title == "HW 3 재채점" && kept.score == 9 && kept.assignmentId == assignment)
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

    /// `10주차-3` said nothing about which class; the day and what it covered do, newest first.
    @Test func importSessionsReadByDayNewestFirst() throws {
        let workspace = try fixtureWorkspace()
        // A makeup set up first, then the class before it: made out of date order on purpose.
        for days in [-1, -2] {
            workspace.run(SessionAdd(course: graphTheory, date: Calendar.current.date(byAdding: .day, value: days, to: .now)!, topic: days == -1 ? "보강" : ""))
        }
        let course = try #require(workspace.course(graphTheory))
        let model = ImportPlaceModel(workspace: workspace, course: course, files: [URL(filePath: "/tmp/a.pdf")], places: [])
        let options = model.sessionOptions.dropFirst()
        let sessions = options.map { id in course.file.sessions.first { $0.id == id.0 }! }
        #expect(sessions.count >= 2 && options.first?.1.hasSuffix(": 보강") == true)
        #expect(model.session == sessions.first?.id)
        #expect(sessions.map(\.date) == sessions.map(\.date).sorted(by: >))
        #expect(options.allSatisfy { $0.1.wholeMatch(of: #/\d{1,2}/\d{1,2}\([월화수목금토일]\)(: .+)?/#) != nil })
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
        let sheet = NewNoteModel(workspace: workspace, course: course, kind: model.filter ?? .free)
        #expect(sheet.link == .units && !sheet.canAdd)
        sheet.title = "  행렬식  "
        sheet.format = .tex
        let id = try #require(sheet.add())
        model.reload()
        #expect(model.shown.map(\.title) == ["행렬식"])
        #expect(model.shown[0].meta.id == id && model.shown[0].format == .tex)
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
        #expect(editor.currentLink == "자유 노트")
        #expect(try course.store.note(id: id)?.meta.kind == .free)
        #expect(NoteEditorModel.markdown(for: URL(filePath: "/x/a b.png"), path: "assets/a b.png") == "![a b](assets/a%20b.png)")
    }

    /// A session's note takes the session's name, as `session note` names it, until the user types their own title.
    @Test func aNewSessionNoteIsNamedAfterItsSession() throws {
        let (workspace, course) = try fixtureCourse()
        let session = try #require(workspace.run(SessionAdd(course: linearAlgebra, date: .now))?.made)
        let sheet = NewNoteModel(workspace: workspace, course: course, kind: .review)
        #expect(sheet.link == .session && sheet.sessionOptions.contains { $0.id == session })
        sheet.sessionId = session
        let file = try #require(workspace.course(linearAlgebra)).file
        let name = file.name(of: try #require(file.sessions.first { $0.id == session }))
        #expect(sheet.title == "\(name) 정리")
        sheet.kind = .rough
        #expect(sheet.title == name)
        sheet.title = "내 제목"
        sheet.kind = .review
        #expect(sheet.title == "내 제목")
        let id = try #require(sheet.add())
        #expect(workspace.course(linearAlgebra)?.file.sessions.first { $0.id == session }?.reviewNoteId == id)
        #expect(!sheet.sessionOptions.contains { $0.id == session })
    }

    /// The picker lists only sessions without this kind's note; a session picked for another kind is dropped rather
    /// than linked, which would take the session from the note it already has.
    @Test func changingKindDropsASessionThatAlreadyHasThatNote() throws {
        let (workspace, course) = try fixtureCourse()
        let session = try #require(workspace.run(SessionAdd(course: linearAlgebra, date: .now))?.made)
        let review = try #require(workspace.run(NoteAdd(course: linearAlgebra, title: "복습", kind: .review, session: session))?.made)
        let sheet = NewNoteModel(workspace: workspace, course: course, kind: .rough)
        sheet.sessionId = session
        sheet.kind = .review
        #expect(sheet.sessionId == nil)
        sheet.title = "다른 복습"
        _ = try #require(sheet.add())
        #expect(workspace.course(linearAlgebra)?.file.sessions.first { $0.id == session }?.reviewNoteId == review)
    }

    /// A block typed into in the read view lands on the lines the parser marked, counted in the same body the editor
    /// holds; lines that changed since are left alone.
    @Test func readViewEditsReplaceTheirOwnLines() throws {
        let (workspace, course) = try fixtureCourse()
        let notes = NotesModel(workspace: workspace, course: course)
        let editor = NoteEditorModel(workspace: workspace, course: course, note: try #require(notes.note(try #require(notes.noteId(titled: "1주차-1")))))
        editor.load()
        editor.body += "\n\n문단 하나\n둘째 줄\n"
        let parsed = ParsedNote(editor.body)
        let last = try #require(Array(parsed.document.children).last)
        let lines = try #require(parsed.lines(of: last))
        #expect(parsed.source(lines) == "문단 하나\n둘째 줄")
        let (from, to) = (lines.lowerBound, lines.upperBound)
        #expect(!editor.replaceLines(from, to, "다른 글", "바뀐 글"))
        #expect(editor.replaceLines(from, to, "문단 하나\n둘째 줄", "바뀐 문단"))
        #expect(editor.body.hasSuffix("\n\n바뀐 문단\n"))
    }
}
