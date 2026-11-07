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

    @Test func whatIsMissingOpensAndTheRestFolds() throws {
        workspace.run(SessionSet(course: graphTheory, session: session, topic: .set("홀의 정리")))
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session, recorded: true)
        #expect(model.items.filter(model.isOpen) == [.progress, .units, .note])
        #expect(model.folded == [.topic, .attendance])
        #expect(model.summary(.topic) == "홀의 정리")
        #expect(model.summary(.attendance) == String(localized: .wrapUpAttendanceRecorded(String(localized: .attendancePresent))))
        model.reopen(.topic)
        #expect(model.items.filter(model.isOpen) == [.progress, .units, .topic, .note])
    }

    @Test func savingWritesEverythingAtOnceAndMarksTheClass() throws {
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        model.add(slides.id)
        model.setRange(slides.id, PageRange(first: 3, last: 9))
        model.pick(unit)
        model.topic = "증가 경로"
        model.attendance = .late
        model.makesNote = true
        #expect(model.refusal == nil)
        model.wrapUp()
        let s = saved
        #expect(s.isWrappedUp)
        #expect(s.materials == [SessionMaterial(materialId: slides.id, firstPage: 3, lastPage: 9)])
        #expect(s.unitIds == [unit] && s.topic == "증가 경로")
        #expect(file.attendance.first { $0.sessionId == session }?.state == .late)
        // Made after the topic was saved, so it carries it in its name.
        let note = try #require(s.roughNoteId.flatMap { id in file.notes.first { $0.id == id } })
        #expect(note.path.contains("증가 경로"))
        #expect(file.wrapUpGaps(of: s).isEmpty)
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
}
