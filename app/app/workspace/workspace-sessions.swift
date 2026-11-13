import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    struct SuggestedSession: Identifiable {
        var courseId: UUID
        var suggestion: SessionPlanner.Suggestion
        /// The session it would be, unsaved: its week places it on the timeline.
        var draft: Session
        var id: UUID { courseId }
    }

    func suggestedSession(for course: LoadedCourse, now: Date) -> SuggestedSession? {
        plan(for: course, now: now, days: 8).first
    }

    /// Every class left in the term that no session stands for yet, for marking ahead (a 휴강 two weeks off).
    func plannedSessions(for course: LoadedCourse, now: Date) -> [SuggestedSession] {
        plan(for: course, now: now, days: nil)
    }

    private func plan(for course: LoadedCourse, now: Date, days: Int?) -> [SuggestedSession] {
        let file = course.file
        let semester = semester(of: file.course)
        return SessionPlanner.planned(
            schedule: file.course.schedule, sessions: file.sessions, from: semester?.start, to: semester?.end,
            examWeeks: semester?.examWeeks ?? [], days: days, now: now, calendar: calendar
        ).map { s in
            let draft = SessionPlanner.session(
                at: s.date, sessions: file.sessions, termStart: semester?.start, calendar: calendar, device: device, now: now)
            return SuggestedSession(courseId: course.id, suggestion: s, draft: draft)
        }
    }

    func suggestedSessions(now: Date) -> [SuggestedSession] {
        currentCourses.compactMap { suggestedSession(for: $0, now: now) }
    }

    /// The session's rough or review note, created from its template the first time.
    func note(_ kind: NoteKind, of sessionId: UUID, in courseId: UUID) -> UUID? {
        run(SessionNote(course: courseId, session: sessionId, kind: kind))?.made
    }

    func setReviewNoteUnfinished(_ unfinished: Bool, of sessionId: UUID, in courseId: UUID) {
        run(SessionSet(course: courseId, session: sessionId, reviewUnfinished: .set(unfinished)))
    }

    func record(_ sessionId: UUID, in courseId: UUID) {
        guard let course = course(courseId), let session = course.file.sessions.first(where: { $0.id == sessionId }) else { return }
        Task { await startRecording(session, in: course) }
    }
}
