import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing
@testable import Folio

/// A graph theory class with the matchings slides tracked and one unit.
@MainActor
struct ClassWrapUpModelTests {
    let workspace: Workspace
    let session: UUID
    let unit: UUID
    let slides: FolioDomain.Material

    init() throws {
        workspace = try fixtureWorkspace()
        workspace.run(MaterialTrack(course: graphTheory))
        session = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-3 * 3600)))?.made)
        unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        slides = try #require(workspace.course(graphTheory)?.file.materials.first { $0.path == "Lectures/05_Matchings.pdf" })
    }

    var file: CourseFile { workspace.course(graphTheory)!.file }
    var saved: Session { file.sessions.first { $0.id == session }! }

    /// A plain form (2026-11-08): every item shows in asking order, filled or not, holding what the class has.
    @Test func everyItemShowsHoldingWhatTheClassHas() throws {
        workspace.run(UnitLink(course: graphTheory, unit: unit, sessions: [session], linked: true))
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session, recorded: true)
        #expect(model.items == [.progress, .units, .note, .attendance])
        #expect(model.items.map(model.label) == ["진도", "단원", "러프 노트", "출석"])
        #expect(model.linkedUnits.map(\.id) == [unit])
        // What the today card asks about is still the class's gaps.
        #expect(file.wrapUpGaps(of: saved, recorded: true) == [.progress, .note])
    }

    /// Attendance is a choice with the likely answer picked, not a line saying why: a recorded class starts on
    /// present, one with an entry on that entry's state, and saving writes what was picked, present as no entry.
    @Test func attendanceStartsOnTheLikelyChoiceAndSavesThePickedOne() throws {
        let recorded = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session, recorded: true)
        #expect(recorded.attendance == .present)
        recorded.attendance = .late
        recorded.wrapUp()
        #expect(file.attendance.first { $0.sessionId == session }?.state == .late)

        let again = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        #expect(again.attendance == .late)
        again.attendance = .present
        again.wrapUp()
        #expect(!file.attendance.contains { $0.sessionId == session })
    }

    @Test func savingWritesEverythingAtOnceAndMarksTheClass() throws {
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        model.add(slides.id)
        model.setRange(slides.id, PageRange(first: 3, last: 9))
        model.pick(unit)
        model.attendance = .late
        model.makesNote = true
        #expect(model.refusal == nil)
        model.wrapUp()
        let s = saved
        #expect(s.isWrappedUp)
        #expect(s.materials == [SessionMaterial(materialId: slides.id, firstPage: 3, lastPage: 9)])
        #expect(s.unitIds == [unit])
        #expect(file.attendance.first { $0.sessionId == session }?.state == .late)
        // Made after the units were saved, so it carries them in its name.
        let note = try #require(s.roughNoteId.flatMap { id in file.notes.first { $0.id == id } })
        #expect(note.path.contains("매칭"))
        #expect(file.wrapUpGaps(of: s).isEmpty)
    }

    /// Progress the class already has shows as its rows, and saving them untouched writes none of them. A file linked
    /// whole (no pages) starts unchecked, so it neither blocks saving nor gets pages it wasn't given.
    @Test func progressTheClassHasIsShownAndLeftAlone() throws {
        let problems = try #require(file.materials.first { $0.path.hasSuffix("Problems.pdf") })
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: session, firstPage: 3, lastPage: 9))
        workspace.run(MaterialLinkSession(course: graphTheory, material: problems.id, session: session))
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session,
                                     viewed: [SessionMaterial(materialId: slides.id, firstPage: 3, lastPage: 14)], recorded: true)
        #expect(model.rows.first { $0.id == slides.id } == .init(id: slides.id, included: true, first: 3, last: 9))
        #expect(model.rows.contains { $0.id == problems.id && !$0.included })
        #expect(model.refusal == nil && model.ranges.isEmpty)
        // Not from the recording: the class had its pages.
        #expect(model.note == nil)
        model.wrapUp()
        #expect(saved.materials == [SessionMaterial(materialId: slides.id, firstPage: 3, lastPage: 9), SessionMaterial(materialId: problems.id)])

        // Checked, the whole-file row asks for its pages; a changed range is the only one written.
        let again = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        again.toggle(problems.id)
        #expect(again.refusal == String(localized: .sessionsProgressMissingLast("Problems.pdf")))
        again.toggle(problems.id)
        again.setRange(slides.id, PageRange(first: 3, last: 12))
        #expect(again.ranges == [SessionMaterial(materialId: slides.id, firstPage: 3, lastPage: 12)])
        again.wrapUp()
        #expect(saved.materials == [SessionMaterial(materialId: slides.id, firstPage: 3, lastPage: 12), SessionMaterial(materialId: problems.id)])
    }

    /// Saving the class's own attendance again leaves its entry as it was.
    @Test func unchangedAttendanceIsNotWrittenAgain() throws {
        workspace.run(AttendanceSet(course: graphTheory, session: session, state: .late))
        let entry = try #require(file.attendance.first { $0.sessionId == session })
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.attendance == .late)
        model.wrapUp()
        #expect(file.attendance.filter { $0.sessionId == session }.map(\.id) == [entry.id])
    }

    /// The case the review found: no lecture files, so progress isn't asked, but the class links an exercise sheet
    /// whole. Saving goes through and leaves that link as it was.
    @Test func aCourseWithoutLecturesSavesPastAWholeFileLink() throws {
        workspace.run(MaterialUntrack(course: graphTheory, material: slides.id))
        let exercise = try #require(file.materials.first { $0.path.hasSuffix("Exercise 1.pdf") })
        workspace.run(MaterialLinkSession(course: graphTheory, material: exercise.id, session: session))
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        #expect(!model.items.contains(.progress))
        #expect(model.refusal == nil)
        model.wrapUp()
        #expect(saved.isWrappedUp && saved.materials == [SessionMaterial(materialId: exercise.id)])
    }

    @Test func aNewUnitIsMadeAtOnceAndChosen() throws {
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        model.newUnit = "  네트워크 흐름 "
        model.addUnit()
        let made = try #require(file.units.first { $0.title == "네트워크 흐름" })
        #expect(model.units == [made.id] && model.newUnit.isEmpty)
        // Nothing of the class is written until it is saved.
        #expect(saved.unitIds.isEmpty)
    }

    @Test func anAssignmentAnnouncedInClassIsAddedToTheCourse() throws {
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        model.assignmentText = "금요일까지 HW9"
        model.addAssignment()
        #expect(file.assignments.contains { $0.title == "HW9" && $0.due != nil })
        #expect(model.assignmentText.isEmpty && model.announced.count == 1)
    }

    @Test func theTodayCardListsTheClassUntilItIsWrappedUp() throws {
        let today = TodayModel(workspace: workspace)
        let now = workspace.now
        let listed = file.classesToWrapUp(at: now, classMinutes: workspace.settings.classMinutes, calendar: workspace.calendar).contains { $0.id == session }
        #expect(today.wrapUps(now: now).contains { $0.session.id == session } == listed)
        ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session).wrapUp()
        #expect(!today.wrapUps(now: now).contains { $0.session.id == session })
    }

    @Test func classesLeftFromEarlierDaysRunOneSheetAfterAnother() throws {
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        let older = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-9 * 86400)))?.made)
        let newer = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-8 * 86400)))?.made)
        let left = model.leftUnwrapped(file).map(\.id)
        let a = try #require(left.firstIndex(of: older)), b = try #require(left.firstIndex(of: newer))
        #expect(a < b)
        #expect(model.gapsLine(model.leftGaps(file.sessions.first { $0.id == older }!, in: file)).contains(String(localized: .wrapUpUnits)))

        model.startWrapUps(file)
        let run = try #require(model.wrapUpRun)
        #expect(run.sessions == left)
        #expect(model.step(of: run) == String(localized: .wrapUpStep(1, left.count)))
        #expect(ClassWrapUpModel(workspace: workspace, course: graphTheory, session: run.current).wrapUp())
        model.wrappedUpOne()
        #expect(model.wrapUpRun?.index == 1)
        // Saved, so neither the notice nor the row's mark lists it, though its gaps were left empty.
        #expect(!model.leftUnwrapped(file).contains { $0.id == run.sessions[0] })
        #expect(model.leftGaps(file.sessions.first { $0.id == run.sessions[0] }!, in: file).isEmpty)
        for _ in 1..<left.count { model.wrappedUpOne() }
        #expect(model.wrapUpRun?.id == nil)
    }

    // MARK: Fixes from using it (2026-11-08)

    /// A file with only a start asks for the end it lacks, by the bar it is picked on, and a one-page range saves.
    @Test func aStartAloneAsksForTheEndAndOnePageSaves() throws {
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        model.add(slides.id)
        #expect(model.rows.first?.range.lone == .first)
        #expect(model.refusal == String(localized: .sessionsProgressMissingLast("05_Matchings.pdf")))
        model.setRange(slides.id, PageRange(first: 1).tapping(1, pages: 20))
        #expect(model.refusal == nil)
        #expect(model.wrapUp())
        #expect(saved.materials == [SessionMaterial(materialId: slides.id, firstPage: 1, lastPage: 1)])
    }

    /// No unit is put forward, not even the last class's: the list is the whole outline and the class has what it was given.
    @Test func unitsArePickedFromTheWholeOutlineAndRemovedOneByOne() throws {
        let earlier = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-2 * 86400)))?.made)
        workspace.run(UnitLink(course: graphTheory, unit: unit, sessions: [earlier], linked: true))
        let flows = try #require(workspace.run(UnitAdd(course: graphTheory, title: "네트워크 흐름"))?.made)
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.units.isEmpty && model.linkedUnits.isEmpty)
        let outline = UnitTree.outline(file.units).map(\.unit.id)
        #expect(model.unitOptions.map(\.id) == outline)
        model.pick(flows)
        model.pick(unit)
        // Chips follow the outline, not the order of picking.
        #expect(model.linkedUnits.map(\.id) == outline.filter { [unit, flows].contains($0) })
        model.removeUnit(flows)
        #expect(model.units == [unit])
        model.wrapUp()
        #expect(saved.unitIds == [unit])
    }

    @Test func theLinkedNoteCanBeSwappedUnlinkedOrMadeAnew() throws {
        let older = try #require(workspace.run(NoteAdd(course: graphTheory, title: "예전 필기"))?.made)
        let newer = try #require(workspace.run(NoteAdd(course: graphTheory, title: "새 필기"))?.made)
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        let choices = model.noteChoices.map(\.id)
        #expect(try #require(choices.firstIndex(of: newer)) < #require(choices.firstIndex(of: older)))

        model.linkNote(older)
        #expect(model.linkedNote?.id == older && saved.roughNoteId == older)
        #expect(!model.noteChoices.contains { $0.id == older })
        model.linkNote(newer)
        #expect(saved.roughNoteId == newer && model.noteChoices.contains { $0.id == older })

        model.unlinkNote()
        #expect(model.linkedNote == nil && saved.roughNoteId == nil && !model.makesNote)
        // The note stays in the course, free to link again.
        #expect(model.noteChoices.contains { $0.id == newer })

        model.linkNote(newer)
        model.makeNewNote()
        #expect(model.linkedNote == nil && model.makesNote)
        model.wrapUp()
        let made = try #require(saved.roughNoteId)
        #expect(made != newer && made != older)
    }

    /// A review note covers other classes too, so the note row only ever swaps or unlinks the class's own note.
    @Test func theNoteRowLeavesAReviewNoteAlone() throws {
        let review = try #require(workspace.run(NoteAdd(course: graphTheory, title: "복습", kind: .review, session: session))?.made)
        let free = try #require(workspace.run(NoteAdd(course: graphTheory, title: "메모"))?.made)
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.linkedNote == nil && !model.makesNote)

        model.linkNote(free)
        #expect(saved.roughNoteId == free && saved.reviewNoteId == review)
        model.unlinkNote()
        #expect(saved.roughNoteId == nil && saved.reviewNoteId == review)

        model.linkNote(free)
        model.makeNewNote()
        #expect(model.makesNote && saved.reviewNoteId == review)
        model.wrapUp()
        let made = try #require(saved.roughNoteId)
        #expect(made != free && saved.reviewNoteId == review)
    }
}
