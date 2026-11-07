import FolioActions
import FolioDomain
import Foundation

/// What a class's menu offers and does, for every screen that shows one: the sessions page, the course overview,
/// Today's list and ribbon. A struct over the workspace, so a row can make one for its own course without keeping state.
@MainActor
struct SessionMenuModel {
    let workspace: Workspace
    let courseId: UUID

    private var calendar: Calendar { workspace.calendar }
    private var file: CourseFile? { workspace.course(courseId)?.file }

    func session(_ id: UUID) -> Session? { file?.sessions.first { $0.id == id } }

    var isRecording: Bool { workspace.recorder.isActive }

    // MARK: A saved session

    /// Only while the class still happens.
    func link(of session: Session) -> URL? {
        guard !session.isCancelled, let file else { return nil }
        return session.link(schedule: file.course.schedule, calendar: calendar)
    }

    func noteLabel(_ kind: NoteKind, of session: Session) -> String {
        switch kind {
        case .rough: String(localized: session.roughNoteId == nil ? .sessionsMakeRoughNote : .sessionsOpenRoughNote)
        default: String(localized: session.reviewNoteId == nil ? .sessionsMakeReviewNote : .sessionsOpenReviewNote)
        }
    }

    /// The note, made from its template the first time.
    func note(_ kind: NoteKind, of session: Session) -> UUID? {
        workspace.note(kind, of: session.id, in: courseId)
    }

    func setReviewNoteUnfinished(_ unfinished: Bool, of session: Session) {
        workspace.setReviewNoteUnfinished(unfinished, of: session.id, in: courseId)
    }

    func setSkipsReview(_ skips: Bool, of session: Session) { workspace.setSkipsReview(skips, of: session.id, in: courseId) }

    func takesAttendance(_ session: Session) -> Bool {
        workspace.can(AttendanceSet(course: courseId, session: session.id, state: .absent))
    }

    func attendance(of session: Session) -> AttendanceState {
        file?.attendance.first { $0.sessionId == session.id }?.state ?? .present
    }

    func setAttendance(_ state: AttendanceState, of session: Session) {
        workspace.run(AttendanceSet(course: courseId, session: session.id, state: state))
    }

    /// Undoing a 휴강 leaves a lecture: a makeup that was cancelled is set back from the form.
    func setCancelled(_ cancelled: Bool, of session: Session) {
        workspace.run(SessionSet(course: courseId, session: session.id, kind: .set(cancelled ? .cancelled : .lecture)))
    }

    func record(_ session: Session) { workspace.record(session.id, in: courseId) }

    func recordings(of session: Session) -> [Recording] { file?.recordings.filter { $0.sessionId == session.id } ?? [] }

    func playLabel(_ index: Int, _ recording: Recording) -> String {
        String(localized: .sessionsPlayRecording(index + 1, RecordingTime.label(recording.duration)))
    }

    func linksUnit(_ unit: UUID, to session: Session) -> Bool { session.unitIds.contains(unit) }

    func toggleUnit(_ unit: UUID, of session: Session) {
        workspace.run(UnitLink(course: courseId, unit: unit, sessions: [session.id], linked: !session.unitIds.contains(unit)))
    }

    // MARK: A class the timetable holds, not saved yet

    func isToday(_ item: Workspace.SuggestedSession) -> Bool { workspace.isStudyToday(item.suggestion.date) }

    func link(of item: Workspace.SuggestedSession) -> URL? { item.suggestion.link.flatMap(OnlineLink.url) }

    /// One action, so an attendance the course refuses leaves no session made for it.
    @discardableResult
    func make(_ item: Workspace.SuggestedSession, kind: Session.Kind = .lecture, attendance: AttendanceState? = nil) -> Session? {
        guard let id = workspace.run(SessionAdd(course: courseId, date: item.suggestion.date, kind: kind, attendance: attendance))?.made else { return nil }
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
