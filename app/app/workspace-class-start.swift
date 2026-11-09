import FolioActions
import FolioDomain
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ClassStartOpening: Equatable {
    var link: AppLink
    var placement: LinkPlacement
}

/// What a window does for a class that has just started: the pages to open, whether to come forward, and whether to
/// ask before recording. Every window watches the same one and the first that takes it clears it
/// (`ClassStartPrompt`), so a class opens once however many windows there are.
struct ClassStartAsk: Identifiable, Equatable {
    let id = UUID()
    let course: UUID
    let session: UUID
    var opens: [ClassStartOpening] = []
    var front = false
    var asksRecording = false
    /// When a recording started for the class stops by itself.
    var stopAt: Date?
    /// `그래프 이론 · 11/2(월)`, as the recording names the class.
    var title = ""
}

/// What one minute's check found for the class starting: the window's part, and whether to record at once.
struct ClassStartStep: Equatable {
    var ask: ClassStartAsk
    var records = false
}

/// A recording the class started, which stops `at` unless it was stopped first.
struct ClassRecordingStop: Equatable {
    var recording: UUID
    var at: Date
}

extension LinkPlacement {
    init(_ place: ClassStartSettings.Place) {
        self = switch place {
        case .here: .here
        case .beside: .beside
        case .tab: .tab
        case .window: .window
        }
    }
}

extension Workspace {
    /// Every window calls this as the minute turns and when it opens, so a class is caught up on whenever the app was
    /// opened during it. Each step of a class is done once (`classStartDone`), and only while the class runs.
    func classStartTick(at now: Date) {
        stopClassRecordingIfDue(at: now)
        guard let step = classStartStep(at: now, recorderBusy: recorder.isActive) else { return }
        if step.records { recordClass(step.ask) }
        guard step.records || step.ask.asksRecording || !step.ask.opens.isEmpty else { return }
        if !step.ask.opens.isEmpty || step.ask.asksRecording { classStartAsk = step.ask }
        if !step.ask.front { NotificationScheduler.classStarted(step.ask.title, recording: step.records) }
    }

    /// Writes what the class's due steps need (its session, its rough note) and says what is left to do. Separate
    /// from the recorder and the windows, so a test runs it on a fixture at a pinned time.
    func classStartStep(at now: Date, recorderBusy: Bool) -> ClassStartStep? {
        guard gist != nil else { return nil }
        let setting = settings.classStart
        let terms = currentCourses.map { ClassStart.Course(file: $0.file, term: semester(of: $0.file.course)) }
        guard let c = ClassStart.starting(terms, settings: settings, now: now, calendar: calendar) else { return nil }
        let done = classStartDone[c.key] ?? []
        let due = ClassStart.due(c, settings: setting, now: now).subtracting(done)
        guard !due.isEmpty else { return nil }
        // Marked before anything runs: a step that fails is reported once, not again every minute. Not the recording
        // while another runs (the class before, kept on until its stop time): it starts the minute that one ends.
        classStartDone[c.key] = done.union(recorderBusy ? due.subtracting([.recording]) : due)
        guard let id = c.sessionId ?? run(SessionAdd(course: c.courseId, date: c.start))?.made,
              let loaded = course(c.courseId), let session = loaded.file.sessions.first(where: { $0.id == id }) else { return nil }
        var step = ClassStartStep(ask: ClassStartAsk(course: loaded.id, session: id, front: setting.screen == .front,
                                                     stopAt: ClassStart.recordingStop(c, settings: setting),
                                                     title: "\(loaded.title) · \(loaded.file.title(of: session, calendar: calendar))"))
        if due.contains(.open) { step.ask.opens = classStartOpenings(for: session, in: loaded.id) }
        // A recording under way is never cut short, and a class recorded already (then stopped, or on another
        // device) isn't recorded again because the app opened during it.
        if due.contains(.recording), !recorderBusy, !loaded.file.recordings.contains(where: { $0.sessionId == id }) {
            switch setting.recording {
            case .start: step.records = true
            case .ask: step.ask.asksRecording = true
            case .off: break
            }
        }
        return step
    }

    /// The rough note and the lectures where the settings put them, and the class itself in front unless the note
    /// took that place. In placement order, so a pane beside opens beside what is then in front.
    func classStartOpenings(for session: Session, in courseId: UUID) -> [ClassStartOpening] {
        let setting = settings.classStart
        var opens: [ClassStartOpening] = []
        if setting.isOn(.roughNote, course: courseId) {
            let made = setting.roughNote == .create ? note(.rough, of: session.id, in: courseId) : session.roughNoteId
            if let made { opens.append(ClassStartOpening(link: AppLink(.note, made), placement: LinkPlacement(setting.roughNotePlace))) }
        }
        if setting.isOn(.lecture, course: courseId), let file = course(courseId)?.file {
            for lecture in file.startingLectures(for: session, all: setting.allLectures, resumes: setting.resumesLecture) {
                opens.append(ClassStartOpening(link: AppLink(.material, lecture.material, anchor: lecture.page.map(AppLink.Anchor.page)),
                                               placement: LinkPlacement(setting.lecturePlace)))
            }
        }
        if !opens.contains(where: { $0.placement == .here }) {
            opens.insert(ClassStartOpening(link: AppLink(.session, session.id), placement: .here), at: 0)
        }
        return LinkPlacement.allCases.flatMap { place in opens.filter { $0.placement == place } }
    }

    /// What a window opens of `ask`, showing `entry` in front: nothing while it shows another class (its session, its
    /// notes, its recording), which the student chose to look at.
    func classStartOpenings(_ ask: ClassStartAsk, showing entry: Navigator.Entry) -> [ClassStartOpening] {
        guard let shown = session(shownBy: entry), shown != ask.session else { return ask.opens }
        return []
    }

    func session(shownBy entry: Navigator.Entry) -> UUID? {
        guard let id = entry.link.id, let file = entry.course.flatMap(course)?.file else { return nil }
        switch entry.link.kind {
        case .session: return id
        case .note: return file.sessions.first { $0.roughNoteId == id || $0.reviewNoteId == id }?.id
        case .recording: return file.recordings.first { $0.id == id }?.sessionId
        default: return nil
        }
    }

    /// From the prompt, too, once the student said yes. The microphone's refusal is the recorder's error, shown as
    /// any other.
    func recordClass(_ ask: ClassStartAsk) {
        guard !recorder.isActive, let loaded = course(ask.course), let session = loaded.file.sessions.first(where: { $0.id == ask.session }) else { return }
        Task {
            await startRecording(session, in: loaded)
            if let stop = ask.stopAt, let id = recorder.current { classRecordingStop = ClassRecordingStop(recording: id, at: stop) }
        }
    }

    /// Only the recording the class started, and only while it is the one running: one started by hand runs on.
    private func stopClassRecordingIfDue(at now: Date) {
        guard let stop = classRecordingStop else { return }
        if recorder.current != stop.recording {
            classRecordingStop = nil
            return
        }
        guard now >= stop.at else { return }
        classRecordingStop = nil
        Task { await stopRecording() }
    }
}

/// Runs the class-start check in every window and shows its part in one: the window in front, or the first to see it
/// while the app is behind.
struct ClassStartPrompt: ViewModifier {
    let workspace: Workspace
    let open: @MainActor (ClassStartOpening) -> Void
    let showing: @MainActor () -> Navigator.Entry
    let bringForward: @MainActor () -> Void
    @State private var asking: ClassStartAsk?
    #if os(macOS)
    @Environment(\.appearsActive) private var active
    #endif

    func body(content: Content) -> some View {
        content
            .onChange(of: workspace.liveNow, initial: true) { workspace.classStartTick(at: workspace.liveNow) }
            .onChange(of: workspace.classStartAsk) { take() }
            #if os(macOS)
            // A window opened at launch is active only after its first check, which then had no window to take it.
            .onChange(of: active) { take() }
            #endif
            .alert(Text(.classStartRecordTitle), isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }), presenting: asking) { ask in
                Button(.classStartRecord) { workspace.recordClass(ask) }
                Button(.commonCancel, role: .cancel) {}
            } message: { ask in
                Text(ask.title)
            }
    }

    func take() {
        guard let ask = workspace.classStartAsk else { return }
        #if os(macOS)
        guard active || !NSApp.isActive else { return }
        #endif
        workspace.classStartAsk = nil
        for opening in workspace.classStartOpenings(ask, showing: showing()) { open(opening) }
        if ask.front { bringForward() }
        if ask.asksRecording { asking = ask }
    }
}

extension View {
    func classStartPrompt(_ workspace: Workspace, open: @escaping @MainActor (ClassStartOpening) -> Void,
                          showing: @escaping @MainActor () -> Navigator.Entry, bringForward: @escaping @MainActor () -> Void) -> some View {
        modifier(ClassStartPrompt(workspace: workspace, open: open, showing: showing, bringForward: bringForward))
    }
}
