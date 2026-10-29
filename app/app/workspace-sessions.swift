import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    struct SuggestedSession: Identifiable {
        var courseId: UUID
        var suggestion: SessionPlanner.Suggestion
        /// What it will be called once made, e.g. `9주차-2`.
        var name: String
        var id: UUID { courseId }
    }

    func suggestedSession(for course: LoadedCourse, now: Date) -> SuggestedSession? {
        let file = course.file
        let semester = semester(of: file.course)
        // A quiz is usually given in class, so only the larger exams take the class time away.
        let exams = file.exams.filter { $0.kind != .quiz }.compactMap { e in
            e.start.map { DateInterval(start: $0, end: max(e.end ?? $0, $0.addingTimeInterval(60))) }
        }
        guard let s = SessionPlanner.suggestion(schedule: file.course.schedule, sessions: file.sessions, from: semester?.start,
                                                to: semester?.end, examWeeks: semester?.examWeeks ?? [], exams: exams,
                                                now: now, calendar: calendar) else { return nil }
        let draft = SessionPlanner.session(at: s.date, sessions: file.sessions, termStart: semester?.start,
                                           calendar: calendar, device: device, now: now)
        return SuggestedSession(courseId: course.id, suggestion: s, name: draft.name(among: file.sessions + [draft]))
    }

    func suggestedSessions(now: Date) -> [SuggestedSession] {
        currentCourses.compactMap { suggestedSession(for: $0, now: now) }
    }

    @discardableResult
    func createSession(at date: Date, cancelled: Bool = false, in courseId: UUID) -> Session? {
        guard let id = run(SessionAdd(course: courseId, date: date, cancelled: cancelled))?.made else { return nil }
        return course(courseId)?.file.sessions.first { $0.id == id }
    }

    /// The session's rough or review note, created from its template the first time (docs/SPEC.md "러프 노트는 처음 열 때 만들어진다").
    func note(_ kind: NoteKind, of sessionId: UUID, in courseId: UUID) -> UUID? {
        run(SessionNote(course: courseId, session: sessionId, kind: kind))?.made
    }

    func setReviewNoteUnfinished(_ unfinished: Bool, of sessionId: UUID, in courseId: UUID) {
        run(SessionSet(course: courseId, session: sessionId, reviewUnfinished: .set(unfinished)))
    }

    func setSkipsReview(_ skips: Bool, of sessionId: UUID, in courseId: UUID) {
        run(SessionSet(course: courseId, session: sessionId, skipsReview: .set(skips)))
    }

    func record(_ sessionId: UUID, in courseId: UUID, locale: Locale) {
        guard let course = course(courseId), let session = course.file.sessions.first(where: { $0.id == sessionId }) else { return }
        Task { await startRecording(session, in: course, locale: locale) }
    }
}
