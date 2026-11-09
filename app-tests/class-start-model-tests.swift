import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

/// The app's side of a class starting (#391): what it writes and what a window is asked to open, on a fixture at a
/// pinned time. The recorder and the windows are left out; the rule itself is tested in ClassStartTests.
@MainActor
struct ClassStartModelTests {
    let workspace: Workspace
    let course = UUID()

    init() throws {
        workspace = try fixtureWorkspace()
        workspace.pinnedNow = at(20)  // a Thursday in the fall term, past its midterm week
        let code = addCode("GS", to: workspace)
        workspace.run(TranscriptAdd(id: course, semester: fallTerm, title: "콜로퀴움", code: code, number: "9331", credits: 0))
        workspace.run(CourseSet(course: course, [.schedule([ClassTime(weekday: 4, startMinute: 21 * 60, endMinute: 22 * 60, room: "Hall")])]))
    }

    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        workspace.calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: hour, minute: minute))!
    }

    /// Only this course: the fixture's own timetable could put another class at the same time.
    func set(_ change: (inout ClassStartSettings) -> Void) {
        var s = workspace.settings
        change(&s.classStart)
        for other in workspace.currentCourses where other.id != course {
            s.classStart.setOff(Set(ClassStartSettings.Item.allCases), for: other.id)
        }
        workspace.saveSettings(s)
    }

    func session(at date: Date) -> Session? { workspace.course(course)?.file.sessions.first { $0.date == date } }

    @Test func theClassOpensOnItsRoughNoteOnce() throws {
        set { $0.roughNote = .create; $0.lecture = .open }
        #expect(workspace.classStartStep(at: at(20, 59)) == nil)
        let step = try #require(workspace.classStartStep(at: at(21, 5)))
        let saved = try #require(session(at: at(21)))
        let note = try #require(saved.roughNoteId)
        #expect(step.ask.session == saved.id && step.ask.course == course)
        // No lecture is linked to the class, so only the note opens, in front.
        #expect(step.ask.opens == [ClassStartOpening(link: AppLink(.note, note), placement: .here)])
        #expect(!step.records && !step.ask.asksRecording && !step.ask.front)
        // Once per class: the next minute has nothing left to do.
        #expect(workspace.classStartStep(at: at(21, 6)) == nil)
    }

    @Test func nothingAfterTheClass() {
        set { $0.roughNote = .create }
        #expect(workspace.classStartStep(at: at(22)) == nil)
        #expect(session(at: at(21)) == nil)
    }

    @Test func theClassItselfOpensWhenNoNoteTakesItsPlace() throws {
        set { $0.roughNote = .openExisting; $0.recording = .ask; $0.screen = .front }
        let step = try #require(workspace.classStartStep(at: at(21)))
        let saved = try #require(session(at: at(21)))
        #expect(saved.roughNoteId == nil)
        #expect(step.ask.opens == [ClassStartOpening(link: AppLink(.session, saved.id), placement: .here)])
        #expect(step.ask.asksRecording && !step.records && step.ask.front)
    }

    @Test func recordsAtOnceUnlessTheClassWasRecorded() throws {
        set { $0.recording = .start; $0.recordingOffsetMinutes = -5; $0.stopsRecording = true; $0.stopAfterMinutes = 5 }
        let early = try #require(workspace.classStartStep(at: at(20, 55)))
        #expect(early.records && early.ask.opens.isEmpty && early.ask.stopAt == at(22, 5))
        let saved = try #require(session(at: at(21)))

        // Opened again during the class, after its recording was stopped: the class isn't recorded twice.
        workspace.classStartDone = [:]
        let gist = try #require(workspace.gist)
        let ctx = ActionContext(gist: gist, device: workspace.device, calendar: workspace.calendar,
                                courses: Dictionary(workspace.courses.map { ($0.id, $0.store) }, uniquingKeysWith: { a, _ in a }))
        try ctx.edit(course) { $0.recordings.append(Recording(device: workspace.device, at: at(20, 55), sessionId: saved.id, file: "Recordings/10-29(목).m4a")) }
        workspace.show(ctx)
        let again = try #require(workspace.classStartStep(at: at(21, 10)))
        #expect(!again.records && again.ask.opens.map(\.link) == [AppLink(.session, saved.id)])
    }

    @Test func aWindowOnAnotherClassIsLeftAlone() throws {
        set { $0.roughNote = .create; $0.roughNotePlace = .tab }
        let step = try #require(workspace.classStartStep(at: at(21)))
        let other = try #require(workspace.run(SessionAdd(course: course, date: at(21) - 7 * 86_400))?.made)
        let elsewhere = Navigator.Entry(link: AppLink(.session, other), course: course)
        #expect(workspace.classStartOpenings(step.ask, showing: elsewhere).isEmpty)
        #expect(workspace.classStartOpenings(step.ask, showing: Navigator.Entry(link: .place(.today))) == step.ask.opens)
        // The class first, then its note in a tab.
        #expect(step.ask.opens.map(\.placement) == [.here, .tab])
    }

    @Test func settingsShowTheOffsetAndTheExceptions() {
        let model = SettingsModel(workspace: workspace, tab: .recording)
        model.load()
        #expect(model.recordingTiming == .onTime)
        model.recordingTiming = .before
        #expect(model.settings.classStart.recordingOffsetMinutes == -SettingsModel.defaultLead)
        model.recordingMinutes = 10
        model.recordingTiming = .after
        #expect(model.settings.classStart.recordingOffsetMinutes == 10)
        model.recordingTiming = .onTime
        #expect(model.settings.classStart.recordingOffsetMinutes == 0)

        #expect(model.exceptionLabel(course) == String(localized: .settingsClassStartFollows))
        model.setFollows(false, .recording, course: course)
        #expect(model.exceptionLabel(course) == "녹음 끔")
        model.setFollows(false, .lecture, course: course)
        #expect(model.exceptionLabel(course) == "녹음 · 렉처 끔")
        model.setFollows(false, .roughNote, course: course)
        #expect(model.exceptionLabel(course) == String(localized: .settingsClassStartAllOff))
        #expect(!model.follows(.roughNote, course: course))
    }
}
