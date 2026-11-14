import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import Folio

@MainActor
struct SessionSheetModelTests {
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

    @Test func everyItemShowsHoldingWhatTheClassHas() throws {
        workspace.run(UnitLink(course: graphTheory, unit: unit, sessions: [session], linked: true))
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session, recorded: true)
        #expect(model.sections == [.progress, .units, .notes, .attendance, .info])
        #expect(model.sections.map(model.label) == ["진도", "단원", "노트", "출결", "수업 정보"])
        #expect(model.linkedUnits.map(\.id) == [unit])
        #expect(file.wrapUpGaps(of: saved, recorded: true) == [.progress, .note])
    }

    @Test func attendanceStartsOnTheLikelyChoiceAndSavesThePickedOne() throws {
        let recorded = SessionSheetModel(workspace: workspace, course: graphTheory, session: session, recorded: true)
        #expect(recorded.attendance == .present)
        recorded.attendance = .late
        recorded.submit()
        #expect(file.attendance.first { $0.sessionId == session }?.state == .late)

        let again = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        #expect(again.attendance == .late)
        again.attendance = .present
        again.submit()
        #expect(!file.attendance.contains { $0.sessionId == session })
    }

    @Test func savingWritesEverythingAtOnceAndMarksTheClass() throws {
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        model.add(slides.id)
        model.setRange(slides.id, PageRange(first: 3, last: 9))
        model.pick(unit)
        model.attendance = .late
        model.makesNote = true
        #expect(model.refusal == nil)
        model.submit()

        let s = saved
        #expect(s.isWrappedUp)
        #expect(s.materials == [SessionMaterial(materialId: slides.id, firstPage: 3, lastPage: 9)])
        #expect(s.unitIds == [unit])
        #expect(file.attendance.first { $0.sessionId == session }?.state == .late)
        let note = try #require(s.roughNoteId.flatMap { id in file.notes.first { $0.id == id } })
        #expect(note.path.contains("매칭"))
        #expect(file.wrapUpGaps(of: s).isEmpty)
    }

    @Test func progressTheClassHasIsShownAndLeftAlone() throws {
        let problems = try #require(file.materials.first { $0.path.hasSuffix("Problems.pdf") })
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: session, firstPage: 3, lastPage: 9))
        workspace.run(MaterialLinkSession(course: graphTheory, material: problems.id, session: session))
        let model = SessionSheetModel(
            workspace: workspace, course: graphTheory, session: session,
            viewed: [SessionMaterial(materialId: slides.id, firstPage: 3, lastPage: 14)], recorded: true)
        #expect(model.rows.first { $0.id == slides.id } == .init(id: slides.id, included: true, first: 3, last: 9))
        #expect(model.rows.contains { $0.id == problems.id && !$0.included })
        #expect(model.refusal == nil && model.ranges.isEmpty)
        #expect(model.note == nil)
        model.submit()
        #expect(
            saved.materials == [
                SessionMaterial(materialId: slides.id, firstPage: 3, lastPage: 9), SessionMaterial(materialId: problems.id),
            ])

        let again = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        again.toggle(problems.id)
        #expect(again.refusal == String(localized: .sessionsProgressMissingLast("Problems.pdf")))
        again.toggle(problems.id)
        again.setRange(slides.id, PageRange(first: 3, last: 12))
        #expect(again.ranges == [SessionMaterial(materialId: slides.id, firstPage: 3, lastPage: 12)])
        again.submit()
        #expect(
            saved.materials == [
                SessionMaterial(materialId: slides.id, firstPage: 3, lastPage: 12), SessionMaterial(materialId: problems.id),
            ])
    }

    @Test func uncheckingALinkedRowRemovesItsProgress() throws {
        let problems = try #require(file.materials.first { $0.path.hasSuffix("Problems.pdf") })
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: session, firstPage: 3, lastPage: 9))
        workspace.run(MaterialLinkSession(course: graphTheory, material: problems.id, session: session))
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session, recorded: true)
        #expect(model.unlinked.isEmpty)
        model.toggle(slides.id)
        #expect(model.unlinked == [slides.id] && model.refusal == nil)
        #expect(model.submit())
        #expect(saved.materials == [SessionMaterial(materialId: problems.id)])
        #expect(file.materials.first { $0.id == slides.id }?.sessionIds.contains(session) == false)

        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: session, firstPage: 3, lastPage: 9))
        let again = SessionSheetModel(workspace: workspace, course: graphTheory, session: session, recorded: true)
        again.toggle(slides.id)
        again.toggle(slides.id)
        #expect(again.unlinked.isEmpty)
    }

    @Test func unchangedAttendanceIsNotWrittenAgain() throws {
        workspace.run(AttendanceSet(course: graphTheory, session: session, state: .late))
        let entry = try #require(file.attendance.first { $0.sessionId == session })
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.attendance == .late)
        model.submit()
        #expect(file.attendance.filter { $0.sessionId == session }.map(\.id) == [entry.id])
    }

    @Test func aCourseWithoutLecturesSavesPastAWholeFileLink() throws {
        workspace.run(MaterialUntrack(course: graphTheory, material: slides.id))
        let exercise = try #require(file.materials.first { $0.path.hasSuffix("Exercise 1.pdf") })
        workspace.run(MaterialLinkSession(course: graphTheory, material: exercise.id, session: session))
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        #expect(!model.sections.contains(.progress))
        #expect(model.refusal == nil)
        model.submit()
        #expect(saved.isWrappedUp && saved.materials == [SessionMaterial(materialId: exercise.id)])
    }

    @Test func aNewUnitIsMadeAtOnceAndChosen() throws {
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        model.makeUnit("  네트워크 흐름 ")
        let made = try #require(file.units.first { $0.title == "네트워크 흐름" })
        #expect(model.units == [made.id])
        #expect(saved.unitIds.isEmpty)
    }

    @Test func theTodayCardListsTheClassUntilItIsWrappedUp() throws {
        let today = TodayModel(workspace: workspace)
        let now = workspace.now
        let listed = file.classesToWrapUp(at: now, classMinutes: workspace.settings.classMinutes, calendar: workspace.calendar).contains {
            $0.id == session
        }
        #expect(today.wrapUps(now: now).contains { $0.session.id == session } == listed)
        SessionSheetModel(workspace: workspace, course: graphTheory, session: session).submit()
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
        #expect(SessionSheetModel(workspace: workspace, course: graphTheory, session: run.current).submit())
        model.wrappedUpOne()
        #expect(model.wrapUpRun?.index == 1)

        #expect(!model.leftUnwrapped(file).contains { $0.id == run.sessions[0] })
        #expect(model.leftGaps(file.sessions.first { $0.id == run.sessions[0] }!, in: file).isEmpty)
        for _ in 1..<left.count { model.wrappedUpOne() }
        #expect(model.wrapUpRun?.id == nil)
    }

    // MARK: Fixes from using it (2026-11-08)

    @Test func aStartAloneAsksForTheEndAndOnePageSaves() throws {
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        model.add(slides.id)
        #expect(model.rows.first?.range.lone == .first)
        #expect(model.refusal == String(localized: .sessionsProgressMissingLast("05_Matchings.pdf")))
        #expect(model.disabled && model.note == model.refusal)
        model.setRange(slides.id, PageRange(first: 1).tapping(1, pages: 20))
        #expect(model.refusal == nil)
        #expect(model.submit())
        #expect(saved.materials == [SessionMaterial(materialId: slides.id, firstPage: 1, lastPage: 1)])
    }

    @Test func unitsArePickedFromTheWholeOutlineAndRemovedOneByOne() throws {
        let earlier = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-2 * 86400)))?.made)
        workspace.run(UnitLink(course: graphTheory, unit: unit, sessions: [earlier], linked: true))
        let flows = try #require(workspace.run(UnitAdd(course: graphTheory, title: "네트워크 흐름"))?.made)
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.units.isEmpty && model.linkedUnits.isEmpty)
        let outline = UnitTree.outline(file.units).map(\.unit.id)
        #expect(model.unitOptions.map(\.id) == outline)

        model.pick(flows)
        model.pick(unit)
        #expect(model.linkedUnits.map(\.id) == outline.filter { [unit, flows].contains($0) })
        model.removeUnit(flows)
        #expect(model.units == [unit])
        model.submit()
        #expect(saved.unitIds == [unit])
    }

    @Test func theLinkedNoteCanBeSwappedUnlinkedOrMadeAnew() throws {
        let older = try #require(workspace.run(NoteAdd(course: graphTheory, title: "예전 필기"))?.made)
        let newer = try #require(workspace.run(NoteAdd(course: graphTheory, title: "새 필기"))?.made)
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        let choices = model.noteChoices.map(\.id)
        #expect(try #require(choices.firstIndex(of: newer)) < #require(choices.firstIndex(of: older)))

        model.linkNote(older)
        #expect(model.linkedNote?.id == older && saved.roughNoteId == older)
        #expect(!model.noteChoices.contains { $0.id == older })
        model.linkNote(newer)
        #expect(saved.roughNoteId == newer && model.noteChoices.contains { $0.id == older })

        model.unlinkNote()
        #expect(model.linkedNote == nil && saved.roughNoteId == nil && !model.makesNote)
        #expect(model.noteChoices.contains { $0.id == newer })

        model.linkNote(newer)
        model.makeNewNote()
        #expect(model.linkedNote == nil && model.makesNote)
        model.submit()
        let made = try #require(saved.roughNoteId)
        #expect(made != newer && made != older)
    }

    @Test func theNoteRowLeavesAReviewNoteAlone() throws {
        let review = try #require(workspace.run(NoteAdd(course: graphTheory, title: "복습", kind: .review, session: session))?.made)
        let free = try #require(workspace.run(NoteAdd(course: graphTheory, title: "메모"))?.made)
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.linkedNote == nil && !model.makesNote)

        model.linkNote(free)
        #expect(saved.roughNoteId == free && saved.reviewNoteId == review)
        model.unlinkNote()
        #expect(saved.roughNoteId == nil && saved.reviewNoteId == review)

        model.linkNote(free)
        model.makeNewNote()
        #expect(model.makesNote && saved.reviewNoteId == review)
        model.submit()
        let made = try #require(saved.roughNoteId)
        #expect(made != free && saved.reviewNoteId == review)
    }

    // MARK: Opened during the class (2026-11-10)

    @Test func duringTheClassASuggestionWaitsUncheckedAndTheUnitsSave() throws {
        let earlier = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-7 * 86_400)))?.made)
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: earlier, firstPage: 1, lastPage: 6))
        let current = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-5 * 60)))?.made)
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: current)
        #expect(model.sections.first == .progress)
        #expect(model.rows == [.init(id: slides.id, included: false, started: false, first: 7, last: nil)])
        #expect(!model.disabled && model.note == nil)
        model.pick(unit)
        #expect(model.submit())
        let s = try #require(file.sessions.first { $0.id == current })
        #expect(s.unitIds == [unit] && s.materials.isEmpty)
        #expect(!s.isWrappedUp)

        let again = SessionSheetModel(workspace: workspace, course: graphTheory, session: current)
        again.setRange(slides.id, PageRange(first: 7))
        #expect(again.rows.first?.included == true)
        #expect(again.disabled && again.note == String(localized: .sessionsProgressMissingLast("05_Matchings.pdf")))
        again.setRange(slides.id, PageRange(first: 7, last: 9))
        #expect(!again.disabled && again.submit())
        #expect(file.sessions.first { $0.id == current }?.materials == [SessionMaterial(materialId: slides.id, firstPage: 7, lastPage: 9)])
    }

    @Test func afterTheClassTheSuggestionIsCheckedAndSaysWhatItLacks() throws {
        let earlier = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-7 * 86_400)))?.made)
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: earlier, firstPage: 1, lastPage: 6))
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.rows == [.init(id: slides.id, included: true, first: 7, last: nil)])
        #expect(model.disabled && model.note == String(localized: .sessionsProgressMissingLast("05_Matchings.pdf")))
    }

    // MARK: One sheet for the class (#403)

    @Test func groupsFollowTheClassAndItsKind() throws {
        let ahead = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(3 * 86400)))?.made)
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: ahead)
        #expect(model.sections == [.info, .units, .notes, .attendance])
        #expect(!model.showsReview)
        model.setKind(.cancelled)
        #expect(model.sections == [.info])

        let adding = SessionSheetModel(workspace: workspace, course: graphTheory, session: nil)
        #expect(adding.sections.first == .info && !adding.sections.contains(.notes) && !adding.sections.contains(.progress))
    }

    @Test func savingWritesTimeReviewAndWrapUpTogether() throws {
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.review == .needed && model.showsReview)
        model.review = .notNeeded
        model.link = "https://zoom.us/j/9"
        model.setKind(.makeup)
        model.pick(unit)
        #expect(model.submit())
        #expect(saved.skipsReview && saved.link == "https://zoom.us/j/9" && saved.kind == .makeup && saved.unitIds == [unit])
        #expect(saved.isWrappedUp)
    }

    @Test func savingAheadOrCancelledIsNotAWrapUp() throws {
        let ahead = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(3 * 86400)))?.made)
        workspace.run(AttendanceSet(course: graphTheory, session: ahead, state: .absent))
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: ahead)
        #expect(model.attendance == .absent)
        model.setKind(.cancelled)
        #expect(model.submit())
        let s = try #require(file.sessions.first { $0.id == ahead })
        #expect(s.isCancelled && !s.isWrappedUp)
        #expect(!file.attendance.contains { $0.sessionId == ahead })
    }

    @Test func addingTakesItsUnitsAndAttendance() throws {
        let start = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: workspace.now.addingTimeInterval(2 * 86_400))!
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: nil, start: start)
        #expect(model.title == String(localized: .sessionsAdd) && model.confirm == String(localized: .commonAdd))
        model.pick(unit)
        model.attendance = .excused
        #expect(model.submit())
        let s = try #require(file.sessions.first { $0.date == start })
        #expect(s.unitIds == [unit])
        #expect(file.attendance.first { $0.sessionId == s.id }?.state == .excused)
    }

    @Test func editingTheClassInfoCountsAsAChange() throws {
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        #expect(!model.changed)
        model.link = "https://zoom.us/j/7"
        #expect(model.changed)
        model.link = saved.link ?? ""
        #expect(!model.changed)
        model.setKind(.makeup)
        #expect(model.changed)
    }
}
