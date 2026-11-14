import FolioActions
import FolioDomain
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

extension LinkPlacement {
    init(_ place: ClassStartSettings.Place) {
        self =
            switch place {
            case .here: .here
            case .beside: .beside
            case .tab: .tab
            case .window: .window
            }
    }
}

extension Workspace {
    func classStartTick(at now: Date) {
        stopClassRecordingIfDue(at: now)
        guard let step = classStartStep(at: now, recorderBusy: recorder.isActive) else { return }
        if step.records { recordClass(step.ask) }
        guard step.records || step.ask.asksRecording || step.ask.opensPages else { return }
        if step.ask.opensPages || step.ask.asksRecording { classStartAsk = step.ask }
        if !step.ask.front { NotificationScheduler.classStarted(step.ask.title, recording: step.records) }
    }

    func classStartStep(at now: Date, recorderBusy: Bool) -> ClassStartStep? {
        guard gist != nil else { return nil }
        let setting = settings.classStart
        let terms = currentCourses.map { ClassStart.Course(file: $0.file, term: semester(of: $0.file.course)) }
        guard let c = ClassStart.starting(terms, settings: settings, now: now, calendar: calendar) else { return nil }
        let done = classStartDone[c.key] ?? []
        let due = ClassStart.due(c, settings: setting, now: now).subtracting(done)
        guard !due.isEmpty else { return nil }

        // 실행하기 전에 표시한다. 그래야 실패한 단계를 매분 다시 보고하지 않고 한 번만 보고한다. 다른 녹음(종료 시각까지
        // 이어지는 앞 수업의 녹음)이 돌고 있으면 녹음은 표시하지 않고, 그 녹음이 끝나는 분에 시작한다.
        classStartDone[c.key] = done.union(recorderBusy ? due.subtracting([.recording]) : due)
        guard let id = c.sessionId ?? run(SessionAdd(course: c.courseId, date: c.start))?.made,
            let loaded = course(c.courseId), let session = loaded.file.sessions.first(where: { $0.id == id })
        else { return nil }
        var step = ClassStartStep(
            ask: ClassStartAsk(
                course: loaded.id, session: id, front: setting.screen == .front,
                stopAt: ClassStart.recordingStop(c, settings: setting),
                title: "\(loaded.title) · \(loaded.file.title(of: session, calendar: calendar))"))

        if due.contains(.open) {
            let pages = classStartPages(for: session, in: loaded.id)
            var links = PanePreset.links(session: session, course: loaded.id)
            links[.lecture] = pages.lectures
            links[.classNote] = pages.note.map { [$0] } ?? []
            if setting.openIn == .splitTab, let split = settings.classStartPreset.startLayout(links) {
                step.ask.split = split
            } else {
                step.ask.opens = classStartOpenings(pages, session: session)
            }
        }

        // 진행 중인 녹음은 중간에 끊지 않는다. 이미 녹음한 수업(그 뒤 멈췄거나 다른 기기에서 녹음한 수업)은 수업 중에 앱을
        // 열었다고 다시 녹음하지 않는다.
        if due.contains(.recording), !recorderBusy, !loaded.file.recordings.contains(where: { $0.sessionId == id }) {
            switch setting.recording {
            case .start: step.records = true
            case .ask: step.ask.asksRecording = true
            case .off: break
            }
        }
        return step
    }

    func classStartPages(for session: Session, in courseId: UUID) -> (note: AppLink?, lectures: [AppLink]) {
        let setting = settings.classStart
        var pages: (note: AppLink?, lectures: [AppLink]) = (nil, [])
        if setting.isOn(.roughNote, course: courseId) {
            let made = setting.roughNote == .create ? note(.rough, of: session.id, in: courseId) : session.roughNoteId
            pages.note = made.map { AppLink(.note, $0) }
        }
        if setting.isOn(.lecture, course: courseId), let file = course(courseId)?.file {
            pages.lectures = file.startingLectures(for: session, all: setting.allLectures, resumes: setting.resumesLecture).map {
                AppLink(.material, $0.material, anchor: $0.page.map(AppLink.Anchor.page))
            }
        }
        return pages
    }

    func classStartOpenings(_ pages: (note: AppLink?, lectures: [AppLink]), session: Session) -> [ClassStartOpening] {
        let setting = settings.classStart
        var opens: [ClassStartOpening] = []
        if let note = pages.note { opens.append(ClassStartOpening(link: note, placement: LinkPlacement(setting.roughNotePlace))) }
        opens += pages.lectures.map { ClassStartOpening(link: $0, placement: LinkPlacement(setting.lecturePlace)) }
        if !opens.contains(where: { $0.placement == .here }) {
            opens.insert(ClassStartOpening(link: AppLink(.session, session.id), placement: .here), at: 0)
        }
        return LinkPlacement.allCases.flatMap { place in opens.filter { $0.placement == place } }
    }

    func classStartOpenings(_ ask: ClassStartAsk, showing entry: Navigator.Entry) -> [ClassStartOpening] {
        leavesAlone(ask, showing: entry) ? [] : ask.opens
    }

    func classStartSplit(_ ask: ClassStartAsk, showing entry: Navigator.Entry) -> PaneLayout? {
        leavesAlone(ask, showing: entry) ? nil : ask.split
    }

    private func leavesAlone(_ ask: ClassStartAsk, showing entry: Navigator.Entry) -> Bool {
        guard let shown = session(shownBy: entry) else { return false }
        return shown != ask.session
    }

    func session(shownBy entry: Navigator.Entry) -> UUID? {
        guard let file = entry.course.flatMap(course)?.file else { return nil }
        return entry.link.kind == .session ? entry.link.id : file.session(holding: entry.link)
    }

    func recordClass(_ ask: ClassStartAsk) {
        guard !recorder.isActive, let loaded = course(ask.course), let session = loaded.file.sessions.first(where: { $0.id == ask.session })
        else { return }
        Task {
            await startRecording(session, in: loaded)
            if let stop = ask.stopAt, let id = recorder.current { classRecordingStop = ClassRecordingStop(recording: id, at: stop) }
        }
    }

    // 직접 시작한 녹음은 계속 돌아야 하므로, 수업이 시작한 녹음이 지금 돌고 있을 때만 멈춘다.
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

extension View {
    func classStartPrompt(
        _ workspace: Workspace, open: @escaping @MainActor (ClassStartOpening) -> Void,
        openSplit: @escaping @MainActor (PaneLayout, UUID) -> Void,
        showing: @escaping @MainActor () -> Navigator.Entry, bringForward: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(ClassStartPrompt(workspace: workspace, open: open, openSplit: openSplit, showing: showing, bringForward: bringForward))
    }
}
