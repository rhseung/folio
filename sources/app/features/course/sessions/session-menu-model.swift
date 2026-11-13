import FolioActions
import FolioDomain
import Foundation

@MainActor
struct SessionMenuModel {
    let workspace: Workspace
    let courseId: UUID

    private var calendar: Calendar { workspace.calendar }
    private var file: CourseFile? { workspace.course(courseId)?.file }

    func session(_ id: UUID) -> Session? { file?.sessions.first { $0.id == id } }

    var isRecording: Bool { workspace.recorder.isActive }

    // MARK: A saved session

    func note(_ kind: NoteKind, of session: Session) -> UUID? {
        workspace.note(kind, of: session.id, in: courseId)
    }

    func attendance(of session: Session) -> AttendanceState {
        file?.attendance.first { $0.sessionId == session.id }?.state ?? .present
    }

    func record(_ session: Session) { workspace.record(session.id, in: courseId) }

    func recordings(of session: Session) -> [Recording] { file?.recordings(of: session) ?? [] }

    // MARK: A class the timetable holds, not saved yet

    func isToday(_ item: Workspace.SuggestedSession) -> Bool { workspace.isStudyToday(item.suggestion.date) }

    func link(of item: Workspace.SuggestedSession) -> URL? { item.suggestion.link.flatMap(OnlineLink.url) }

    // 과목이 출결을 거절할 때 회차만 만들어지지 않도록 액션 하나로 한다.
    @discardableResult
    func make(_ item: Workspace.SuggestedSession, kind: Session.Kind = .lecture, attendance: AttendanceState? = nil) -> Session? {
        guard let id = workspace.run(SessionAdd(course: courseId, date: item.suggestion.date, kind: kind, attendance: attendance))?.made
        else { return nil }
        return session(id)
    }

    func canMark(_ item: Workspace.SuggestedSession, _ attendance: AttendanceState) -> Bool {
        workspace.can(SessionAdd(course: courseId, date: item.suggestion.date, attendance: attendance))
    }

    func roughNote(_ item: Workspace.SuggestedSession) -> UUID? {
        make(item).flatMap { note(.rough, of: $0) }
    }

    func record(_ item: Workspace.SuggestedSession) {
        if let s = make(item) { record(s) }
    }
}

extension Session.Kind {
    static var options: [(Session.Kind, String)] {
        [
            (.lecture, String(localized: .sessionsLecture)), (.cancelled, String(localized: .sessionsCancelled)),
            (.makeup, String(localized: .sessionsMakeup)),
        ]
    }
}
