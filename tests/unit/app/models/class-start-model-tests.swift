import FolioActions
import FolioDomain
import Foundation
import Testing

@testable import Folio

@MainActor
struct ClassStartModelTests {
    let workspace: Workspace
    let course = UUID()

    init() throws {
        workspace = try fixtureWorkspace()
        workspace.pinnedNow = at(20)  // 가을학기의 목요일이며, 중간고사 주가 지났다.
        let code = addCode("GS", to: workspace)
        workspace.run(TranscriptAdd(id: course, semester: fallTerm, title: "콜로퀴움", code: code, number: "9331", credits: 0))
        workspace.run(
            CourseSet(course: course, [.schedule([ClassTime(weekday: 4, startMinute: 21 * 60, endMinute: 22 * 60, room: "Hall")])]))
    }

    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        workspace.calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: hour, minute: minute))!
    }

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
        set {
            $0.roughNote = .create; $0.lecture = .open; $0.openIn = .currentTab
        }
        #expect(workspace.classStartStep(at: at(20, 59), recorderBusy: false) == nil)
        let step = try #require(workspace.classStartStep(at: at(21, 5), recorderBusy: false))
        let saved = try #require(session(at: at(21)))
        let note = try #require(saved.roughNoteId)
        #expect(step.ask.session == saved.id && step.ask.course == course)
        #expect(step.ask.opens == [ClassStartOpening(link: AppLink(.note, note), placement: .here)])
        #expect(!step.records && !step.ask.asksRecording && !step.ask.front)
        #expect(workspace.classStartStep(at: at(21, 6), recorderBusy: false) == nil)
    }

    @Test func thePagesOpenSideBySideInANewTab() throws {
        set {
            $0.roughNote = .create; $0.lecture = .open
        }
        let gist = try #require(workspace.gist)
        let ctx = ActionContext(
            gist: gist, device: workspace.device, calendar: workspace.calendar,
            courses: Dictionary(workspace.courses.map { ($0.id, $0.store) }, uniquingKeysWith: { a, _ in a }))
        let path = "Lectures/09_Flows.pdf"
        let lecture = Material(device: workspace.device, at: at(9), path: path, role: MaterialRole(path: path), status: .classified)
        let planned = Session(device: workspace.device, at: at(9), week: 9, date: at(21))
        try ctx.edit(course) { file in
            file.materials.append(lecture)
            file.sessions.append(planned)
            file.linkMaterial(lecture.id, session: planned.id)
        }
        workspace.show(ctx)

        let step = try #require(workspace.classStartStep(at: at(21, 5), recorderBusy: false))
        let note = try #require(session(at: at(21))?.roughNoteId)
        let split = try #require(step.ask.split)
        #expect(split.links == [AppLink(.material, lecture.id), AppLink(.note, note)])
        #expect(split.shares == PanePreset.inClass.shares && split.focus == 1)
        #expect(step.ask.opens.isEmpty)
    }

    @Test func theChosenLayoutOpensTheClass() throws {
        let saved = PanePreset(name: "노트와 성적", slots: [.link(.place(.grades)), .role(.classNote)], shares: [0.3, 0.7])
        var s = workspace.settings
        s.panePresets = [saved]
        workspace.saveSettings(s)
        set {
            $0.roughNote = .create; $0.preset = saved.id
        }
        let step = try #require(workspace.classStartStep(at: at(21, 5), recorderBusy: false))
        let note = try #require(session(at: at(21))?.roughNoteId)
        let split = try #require(step.ask.split)
        #expect(split.links == [.place(.grades), AppLink(.note, note)] && split.shares == saved.shares && split.focus == 1)
    }

    @Test func withoutPagesTheClassOpensInFront() throws {
        set { $0.roughNote = .openExisting }
        let step = try #require(workspace.classStartStep(at: at(21), recorderBusy: false))
        let saved = try #require(session(at: at(21)))
        #expect(step.ask.split == nil && step.ask.opens == [ClassStartOpening(link: AppLink(.session, saved.id), placement: .here)])
    }

    @Test func nothingAfterTheClass() {
        set { $0.roughNote = .create }
        #expect(workspace.classStartStep(at: at(22), recorderBusy: false) == nil)
        #expect(session(at: at(21)) == nil)
    }

    @Test func theClassItselfOpensWhenNoNoteTakesItsPlace() throws {
        set {
            $0.roughNote = .openExisting; $0.recording = .ask; $0.screen = .front
        }
        let step = try #require(workspace.classStartStep(at: at(21), recorderBusy: false))
        let saved = try #require(session(at: at(21)))
        #expect(saved.roughNoteId == nil)
        #expect(step.ask.opens == [ClassStartOpening(link: AppLink(.session, saved.id), placement: .here)])
        #expect(step.ask.asksRecording && !step.records && step.ask.front)
    }

    @Test func recordsAtOnceUnlessTheClassWasRecorded() throws {
        set {
            $0.recording = .start; $0.recordingOffsetMinutes = -5; $0.stopsRecording = true; $0.stopAfterMinutes = 5
        }
        let early = try #require(workspace.classStartStep(at: at(20, 55), recorderBusy: false))
        #expect(early.records && early.ask.opens.isEmpty && early.ask.stopAt == at(22, 5))
        let saved = try #require(session(at: at(21)))

        workspace.classStartDone = [:]
        let gist = try #require(workspace.gist)
        let ctx = ActionContext(
            gist: gist, device: workspace.device, calendar: workspace.calendar,
            courses: Dictionary(workspace.courses.map { ($0.id, $0.store) }, uniquingKeysWith: { a, _ in a }))
        try ctx.edit(course) {
            $0.recordings.append(Recording(device: workspace.device, at: at(20, 55), sessionId: saved.id, file: "Recordings/10-29(목).m4a"))
        }
        workspace.show(ctx)
        let again = try #require(workspace.classStartStep(at: at(21, 10), recorderBusy: false))
        #expect(!again.records && again.ask.opens.map(\.link) == [AppLink(.session, saved.id)])
    }

    @Test func theRecordingWaitsForTheOneBeforeToStop() throws {
        set {
            $0.recording = .start; $0.roughNote = .create
        }
        let busy = try #require(workspace.classStartStep(at: at(21), recorderBusy: true))
        #expect(!busy.records && busy.ask.opensPages)
        let free = try #require(workspace.classStartStep(at: at(21, 5), recorderBusy: false))
        #expect(free.records && !free.ask.opensPages)
        #expect(workspace.classStartStep(at: at(21, 6), recorderBusy: false) == nil)
    }

    @Test func aWindowOnAnotherClassIsLeftAlone() throws {
        set {
            $0.roughNote = .create; $0.roughNotePlace = .tab; $0.openIn = .currentTab
        }
        let step = try #require(workspace.classStartStep(at: at(21), recorderBusy: false))
        let other = try #require(workspace.run(SessionAdd(course: course, date: at(21) - 7 * 86_400))?.made)
        let elsewhere = Navigator.Entry(link: AppLink(.session, other), course: course)
        #expect(workspace.classStartOpenings(step.ask, showing: elsewhere).isEmpty)
        #expect(workspace.classStartOpenings(step.ask, showing: Navigator.Entry(link: .place(.today))) == step.ask.opens)
        #expect(step.ask.opens.map(\.placement) == [.here, .tab])

        var split = step.ask
        split.opens = []
        split.split = PaneLayout(AppLink(.session, other))
        #expect(workspace.classStartSplit(split, showing: elsewhere) == nil)
        #expect(workspace.classStartSplit(split, showing: Navigator.Entry(link: .place(.today))) == split.split)
    }

    @Test func settingsChipsKeepEachItemsWay() {
        let model = SettingsModel(workspace: workspace, tab: .classes)
        model.load()
        #expect(model.classStartItems.isEmpty)
        model.classStartItems = [.recording, .roughNote, .lecture]
        #expect(
            model.settings.classStart.recording == .start && model.settings.classStart.roughNote == .create
                && model.settings.classStart.lecture == .open)
        model.settings.classStart.recording = .ask
        model.settings.classStart.roughNote = .openExisting
        model.classStartItems = [.lecture]
        #expect(model.settings.classStart.recording == .off && model.settings.classStart.roughNote == .off)
        model.classStartItems = [.recording, .roughNote, .lecture]
        #expect(model.settings.classStart.recording == .ask && model.settings.classStart.roughNote == .openExisting)
    }

    @Test func settingsShowTheSpanAtARealClass() throws {
        let model = SettingsModel(workspace: workspace, tab: .classes)
        model.load()
        model.settings.classStart.recordingOffsetMinutes = -5
        let c = try #require(model.referenceClass)
        #expect(c.end > workspace.liveNow)
        let start = SettingsModel.clock(c.start.addingTimeInterval(-300))
        #expect(model.recordingSpanTimes == "\(start) – \(String(localized: .settingsClassStartManualStop))")
        model.settings.classStart.stopsRecording = true
        model.settings.classStart.stopAfterMinutes = -10
        #expect(model.recordingSpanTimes == "\(start) – \(SettingsModel.clock(c.end.addingTimeInterval(-600)))")
    }

    @Test func settingsShowTheExceptions() {
        let model = SettingsModel(workspace: workspace, tab: .classes)
        model.load()
        #expect(model.exceptionLabel(course) == String(localized: .settingsClassStartFollows))
        model.setFollows(false, .recording, course: course)
        #expect(model.exceptionLabel(course) == "녹음 제외")
        model.setFollows(false, .lecture, course: course)
        #expect(model.exceptionLabel(course) == "녹음 · 렉처 제외")
        model.setFollows(false, .roughNote, course: course)
        #expect(model.exceptionLabel(course) == String(localized: .settingsClassStartAllOff))
        #expect(!model.follows(.roughNote, course: course))
    }
}
