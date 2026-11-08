import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
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
    /// Each file opens on its own guess, and the destination shows the name it will get before anything is copied.
    @Test func importRowsOpenOnTheirGuessAndShowTheirNames() throws {
        let (workspace, course) = try fixtureCourse()
        let model = ImportPlaceModel(workspace: workspace, course: course,
                                     files: ["HW2.pdf", "01_Vectors.pdf", "Notes.pdf"].map { URL(filePath: "/tmp/\($0)") },
                                     places: MaterialIntake.places(assignmentFolders: ["HW01", "HW02"]))
        #expect(model.title == "파일 3개 넣기" && model.confirmTitle == "3개 넣기")
        #expect(model.rows.map(\.folder) == ["Assignments/HW02", "Lectures", "Lectures"])
        #expect(model.kindLabel(model.rows[0]) == "과제 HW02")
        #expect(model.kindWhy(model.rows[0]) == "추측: 이름의 HW2")
        // Nothing about Notes.pdf pointed anywhere: it sits in Lectures without a ✦.
        #expect(model.kindWhy(model.rows[2]) == nil)
        let placements = model.placements
        #expect(placements[1].path == "Lectures/01_Vectors 2.pdf" && placements[1].suffix == " 2")
        #expect(model.nameNote(placements[1]) == "같은 이름이 있어 뒤에 2를 붙입니다")
        // A changed row loses its ✦.
        model.setFolder("Assignments/HW01", for: [0])
        #expect(model.kindWhy(model.rows[0]) == nil)
    }

    /// ⇧ widens from the last pick, ⌘ adds one, and a menu or number key on a selected row changes every selected row.
    @Test func severalSelectedRowsChangeTogether() throws {
        let (workspace, course) = try fixtureCourse()
        let model = ImportPlaceModel(workspace: workspace, course: course, files: (1...4).map { URL(filePath: "/tmp/\($0).pdf") },
                                     places: MaterialIntake.places(assignmentFolders: ["HW01", "HW02"]))
        model.click(1)
        model.click(2, extend: true)
        model.click(0, toggle: true)
        #expect(model.selection == [0, 1, 2])
        let textbooks = try #require(model.kinds.first { $0.places == ["Textbooks"] })
        model.setKind(textbooks, for: model.targets(model.rows[1]))
        #expect(model.rows.map(\.folder) == ["Textbooks", "Textbooks", "Textbooks", "Lectures"])
        // A row outside the selection changes alone.
        #expect(model.targets(model.rows[3]) == [3])
        let assignments = try #require(model.kinds.firstIndex { $0.perItem })
        #expect(model.applyKind(number: assignments + 1))
        // The newest assignment: the likely one.
        #expect(model.rows.prefix(3).allSatisfy { $0.folder == "Assignments/HW02" })
        model.step(1, extend: false)
        #expect(model.selection == [1])
        model.step(1, extend: true)
        #expect(model.selection == [1, 2])
    }

    /// A touch screen's way to several rows: a long press starts with that row, a tap adds or takes one away, and taking
    /// the last one away ends the pick, so a tap picks one row again.
    @Test func aHoldStartsATouchPick() throws {
        let (workspace, course) = try fixtureCourse()
        let model = ImportPlaceModel(workspace: workspace, course: course, files: (1...4).map { URL(filePath: "/tmp/\($0).pdf") },
                                     places: MaterialIntake.places(assignmentFolders: ["HW01"]))
        model.click(0)
        model.hold(2)
        #expect(model.picking)
        #expect(model.selection == [2])
        model.press(0, .toggle)
        model.press(3, .toggle)
        model.press(2, .toggle)
        #expect(model.selection == [0, 3])
        model.press(0, .toggle)
        model.press(3, .toggle)
        #expect(!model.picking)
        model.press(1, .only)
        #expect(model.selection == [1])
    }

    /// The day and units say which class it was; newest first.
    @Test func importSessionsReadByDayNewestFirst() throws {
        let workspace = try fixtureWorkspace()
        // A makeup set up first, then the class before it: made out of date order on purpose.
        let makeup = UUID()
        for days in [-1, -2] {
            workspace.run(SessionAdd(id: days == -1 ? makeup : UUID(), course: graphTheory, date: Calendar.current.date(byAdding: .day, value: days, to: .now)!))
        }
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "보강"))?.made)
        workspace.run(UnitLink(course: graphTheory, unit: unit, sessions: [makeup], linked: true))
        let course = try #require(workspace.course(graphTheory))
        let model = ImportPlaceModel(workspace: workspace, course: course, files: [URL(filePath: "/tmp/a.pdf")], places: [])
        let sessions = model.sessions
        #expect(sessions.count >= 2 && model.sessionTitle(sessions[0]).hasSuffix(": 보강"))
        #expect(sessions.map(\.date) == sessions.map(\.date).sorted(by: >))
        #expect(sessions.map(model.sessionTitle).allSatisfy { $0.wholeMatch(of: #/\d{1,2}/\d{1,2}\([월화수목금토일]\)(: .+)?/#) != nil })
        // A file with nothing to say goes to the latest class.
        #expect(model.rows[0].session == sessions[0].id && model.sessionLabel(model.rows[0]).hasSuffix(": 보강"))
        model.setSession(nil, for: [0])
        #expect(model.sessionLabel(model.rows[0]) == "회차 없음")
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

    /// The move menu asks with the action's own words; the rename alert already shows the new name, so it doesn't.
    @Test func movingAFileAsksButRenamingDoesNot() throws {
        let (workspace, course) = try fixtureCourse()
        workspace.run(MaterialTrack(course: linearAlgebra))
        let model = MaterialsModel(workspace: workspace, course: course)
        let m = try #require(model.materials.first { $0.isPDF && !model.moveTargets($0).isEmpty })
        let place = try #require(model.moveTargets(m).first)
        model.move(m, into: place)
        let pending = try #require(model.pending)
        #expect(pending.question.hasSuffix("(으)로 옮깁니다.") && pending.question.contains(place) && pending.refusal == nil)
        #expect(model.materials.first { $0.id == m.id }?.path == m.path && model.moves.batch == nil)
        pending.perform()
        let moved = try #require(model.materials.first { $0.id == m.id })
        #expect(moved.path.hasPrefix(place + "/") && model.moves.batch != nil)

        model.pending = nil
        model.startRenaming(moved)
        model.newName = "새 이름"
        model.rename(moved)
        #expect(model.pending == nil && model.materials.first { $0.id == m.id }?.path == "\(place)/새 이름.pdf")
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

        model.filter = .unit
        #expect(model.emptyLine == "단원 노트가 없습니다")
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
        #expect(model.parts.map(\.title) == ["수업 노트", "단원 노트"])
        var closed = false
        model.delete(model.shown.first { $0.meta.id == id }!) { closed = true }
        #expect(!closed && model.parts.map(\.title) == ["수업 노트", "단원 노트"])
        try #require(model.pending).perform()
        #expect(closed && model.parts.map(\.title) == ["수업 노트"])
    }

    /// The sheet shows the name the note will get, ` 2` included, and saving it is the approval. The open note is found
    /// again by its ID at the new path, and the list re-reads it.
    @Test func renamingShowsTheNewFileNameAndKeepsTheNoteOpen() throws {
        let (workspace, course) = try fixtureCourse()
        let id = try #require(workspace.run(NoteAdd(course: linearAlgebra, title: "행렬식"))?.made)
        try #require(workspace.run(NoteAdd(course: linearAlgebra, title: "고윳값")))
        let note = try #require(try course.store.note(id: id))
        let sheet = NoteRenameModel(workspace: workspace, course: course, note: note)
        #expect(!sheet.canSave)
        sheet.name = "  "
        #expect(!sheet.canSave && sheet.message == "새 이름을 적습니다.")
        sheet.name = "고윳값"
        #expect(sheet.target == "고윳값 2.md" && sheet.message.hasPrefix("Notes/고윳값 2.md(으)로 바꿉니다."))
        sheet.name = "a/b"
        #expect(sheet.target == "a-b.md")
        let revision = workspace.notesRevision
        #expect(sheet.rename())
        #expect(workspace.notesRevision > revision)
        let notes = NotesModel(workspace: workspace, course: course)
        #expect(notes.note(id)?.title == "a-b")
    }

    /// A `.tex` note's sheet shows its built PDF taking the new name, which the rename then does.
    @Test func renamingATexNoteShowsItsBuiltPDF() throws {
        let (workspace, course) = try fixtureCourse()
        let id = try #require(workspace.run(NoteAdd(course: linearAlgebra, title: "증명", format: .tex))?.made)
        let note = try #require(try course.store.note(id: id))
        let output = TexEngine.outputFolder(for: note.url)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("%PDF".utf8).write(to: output.appending(path: "built.pdf"))
        try #require(workspace.run(NoteBuild(course: linearAlgebra, note: "Notes/증명.tex", pdf: output.appending(path: "built.pdf").path)))
        let sheet = NoteRenameModel(workspace: workspace, course: course, note: note)
        #expect(sheet.pdfName == nil)
        sheet.name = "귀류법"
        #expect(sheet.pdfName == "Study/귀류법.pdf" && sheet.pdfDetail == "Folio가 빌드한 Study/증명.pdf도 이름을 따라 바꿉니다")
        #expect(sheet.rename())
        #expect(FileManager.default.fileExists(atPath: course.store.fileURL("Study/귀류법.pdf").path))
    }

    /// Moving asks first, with the name the note will have in the folder.
    @Test func movingIntoAFolderAsksWithTheNewPath() throws {
        let (workspace, course) = try fixtureCourse()
        let id = try #require(workspace.run(NoteAdd(course: linearAlgebra, title: "행렬식"))?.made)
        try FileManager.default.createDirectory(at: course.store.url.appending(path: "Notes/정리"), withIntermediateDirectories: true)
        let model = NoteListModel(workspace: workspace, course: course)
        model.reload()
        let note = try #require(model.notes.first { $0.meta.id == id })
        #expect(model.moveTargets(note) == ["정리"] && model.folderLabel("정리") == "Notes/정리" && model.folderLabel("") == "Notes")
        model.move(note, into: "정리")
        let pending = try #require(model.pending)
        #expect(pending.question.contains("Notes/정리/행렬식.md"))
        pending.perform()
        let moved = try #require(model.notes.first { $0.meta.id == id })
        #expect(course.store.coursePath(of: moved.url) == "Notes/정리/행렬식.md" && model.moveTargets(moved) == [""])
    }

    /// With no folder in Notes/ yet, a note still moves into a new one; the sheet names the folder it makes and refuses
    /// names a note can't be in.
    @Test func movingIntoANewFolderMakesIt() throws {
        let (workspace, course) = try fixtureCourse()
        let id = try #require(workspace.run(NoteAdd(course: linearAlgebra, title: "행렬식"))?.made)
        let note = try #require(try course.store.note(id: id))
        let sheet = NoteFolderModel(workspace: workspace, course: course, note: note)
        #expect(!sheet.canSave && sheet.message == "새 폴더 이름을 적습니다.")
        for name in ["assets", "Exports", ".숨김", "정리/증명"] {
            sheet.name = name
            #expect(!sheet.canSave, "\(name)")
        }
        sheet.name = " 중간 대비 "
        #expect(sheet.target == "중간 대비/행렬식.md" && sheet.message == "폴더 Notes/중간 대비을(를) 만들고 Notes/중간 대비/행렬식.md(으)로 옮깁니다.")
        #expect(sheet.move())
        let list = NoteListModel(workspace: workspace, course: course)
        list.reload()
        let moved = try #require(list.notes.first { $0.meta.id == id })
        #expect(course.store.coursePath(of: moved.url) == "Notes/중간 대비/행렬식.md" && list.folders == ["", "중간 대비"])
        let again = NoteFolderModel(workspace: workspace, course: course, note: moved)
        again.name = "중간 대비"
        #expect(!again.canSave && again.message == "노트가 이미 이 폴더에 있습니다.")
    }

    /// A rename from the open note's sheet lands in the list's undo, which asks with `cleanup undo`'s words and puts the
    /// note's name back; the list's own moves land there too.
    @Test func theListUndoesTheLastNoteMove() throws {
        let (workspace, course) = try fixtureCourse()
        let id = try #require(workspace.run(NoteAdd(course: linearAlgebra, title: "행렬식"))?.made)
        let moves = MoveUndo()
        let list = NoteListModel(workspace: workspace, course: course, moves: moves)
        list.reload()
        let sheet = NoteRenameModel(workspace: workspace, course: course, note: try #require(try course.store.note(id: id)), moves: moves)
        sheet.name = "고윳값"
        #expect(moves.batch == nil && sheet.rename() && moves.batch != nil)

        list.undoMove()
        let pending = try #require(list.pending)
        #expect(pending.question.hasSuffix("의 이동을 되돌립니다.") && pending.refusal == nil)
        pending.perform()
        #expect(moves.batch == nil && list.notes.first { $0.meta.id == id }?.title == "행렬식")

        let note = try #require(list.notes.first { $0.meta.id == id })
        let folder = NoteFolderModel(workspace: workspace, course: course, note: note, moves: moves)
        folder.name = "정리"
        #expect(folder.move() && moves.batch != nil)
    }

    @Test func editorNamesItsLinkAndFindsNotesByTitle() throws {
        let (workspace, course) = try fixtureCourse()
        let notes = NotesModel(workspace: workspace, course: course)
        let id = try #require(notes.noteId(titled: "03-03(화)"))
        #expect(notes.noteId(titled: "03-03(화)".uppercased()) == id)
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

    /// Classes caught up on together share one review note: picking a class in the link menu adds it, picking it again
    /// takes it off, and the list names the classes it covers.
    @Test func aReviewNoteCoversTheClassesPicked() throws {
        let (workspace, course) = try fixtureCourse()
        let day: TimeInterval = 86_400
        let first = try #require(workspace.run(SessionAdd(course: linearAlgebra, date: .now - 9 * day))?.made)
        let second = try #require(workspace.run(SessionAdd(course: linearAlgebra, date: .now - 2 * day))?.made)
        let id = try #require(workspace.run(NoteAdd(course: linearAlgebra, title: "밀린 복습", kind: .review, session: first))?.made)
        let editor = NoteEditorModel(workspace: workspace, course: course, note: try #require(try course.store.note(id: id)))
        editor.load()
        editor.pick(second, as: .review)
        #expect(editor.linkedSessions.map(\.id) == [first, second] && editor.meta.sessionIds == [first, second])
        let file = try #require(workspace.course(linearAlgebra)).file
        #expect([first, second].allSatisfy { s in file.sessions.first { $0.id == s }?.reviewNoteId == id })
        let span = try #require(file.sessionSpan(of: id, calendar: workspace.calendar))
        #expect(editor.currentLink == "\(span) 복습 노트")
        let list = NoteListModel(workspace: workspace, course: course)
        list.reload()
        #expect(list.parts.first?.rows.first { $0.note.meta.id == id }?.detail == "\(span) · 복습")
        editor.pick(first, as: .review)
        #expect(editor.linkedSessions.map(\.id) == [second])
    }

    /// A session's note takes the session's date and subject, as `session note` names it, until the user types their own title.
    @Test func aNewSessionNoteIsNamedAfterItsSession() throws {
        let (workspace, course) = try fixtureCourse()
        let session = try #require(workspace.run(SessionAdd(course: linearAlgebra, date: .now))?.made)
        let sheet = NewNoteModel(workspace: workspace, course: course, kind: .review)
        #expect(sheet.link == .session && sheet.sessionOptions.contains { $0.id == session })
        sheet.sessionId = session
        let file = try #require(workspace.course(linearAlgebra)).file
        let name = file.noteTitle(for: try #require(file.sessions.first { $0.id == session }), kind: .rough, calendar: workspace.calendar)
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
        let editor = NoteEditorModel(workspace: workspace, course: course, note: try #require(notes.note(try #require(notes.noteId(titled: "03-03(화)")))))
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

/// 그래프 이론's HW03 holds PDFs; a `.tex` is made beside them.
@MainActor
struct AssignmentSheetOpenTests {
    /// Every file opens in the materials tab's file view (#179). With nothing typed the sheet gives way; holding edits
    /// it stays and the file opens in a new window, or, with no other window to open, it asks first (#317).
    @Test func aFileOpensInTheMaterialsTabAndAsksAboutEdits() throws {
        let workspace = try fixtureWorkspace()
        workspace.run(MaterialTrack(course: graphTheory))
        let assignment = try #require(workspace.course(graphTheory)?.file.assignments.first { AssignmentFiles.path(of: $0) == "Assignments/HW03" })
        workspace.run(MaterialNew(course: graphTheory, folder: "Assignments/HW03", name: "hw3.tex"))
        let course = try #require(workspace.course(graphTheory))
        let sheet = AssignmentSheetModel(workspace: workspace, course: course, assignment: assignment)
        sheet.load()
        let tex = try #require(sheet.files.first { $0.path == "Assignments/HW03/hw3.tex" })
        let pdf = try #require(sheet.files.first { $0.isPDF })
        let memo = { workspace.course(graphTheory)?.file.assignments.first { $0.id == assignment.id }?.memo }

        #expect(!sheet.edited)
        #expect(sheet.open(pdf, windows: true) == .materials(pdf.id))
        #expect(sheet.open(tex, windows: true) == .materials(tex.id))
        #expect(sheet.open(tex, windows: false) == .materials(tex.id))
        #expect(sheet.opening == nil)

        sheet.memo = "풀이 방향 메모"
        #expect(sheet.edited)
        // With edits the sheet stays, and the file opens in a window of its own; with no other window to open, it asks.
        #expect(sheet.open(pdf, windows: true) == .window(pdf.id) && sheet.opening == nil)
        #expect(sheet.open(pdf, windows: false) == .asks && sheet.opening?.id == pdf.id)
        sheet.opening = nil
        #expect(sheet.open(tex, windows: true) == .window(tex.id) && sheet.opening == nil)
        #expect(sheet.open(tex, windows: false) == .asks && sheet.opening?.id == tex.id)
        sheet.discardAndOpen()
        #expect(sheet.opening == nil)
        #expect(memo() == assignment.memo)

        #expect(sheet.open(tex, windows: false) == .asks)
        #expect(sheet.saveAndOpen())
        #expect(sheet.opening == nil)
        #expect(memo() == "풀이 방향 메모")
    }
}
