import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

struct NoteLinks {
    var kind: NoteKind
    var session: Session.ID?
    var exam: Exam.ID?
    var units: [FolioDomain.Unit.ID]

    func apply(to meta: inout NoteMeta, in course: CourseFile, calendar: Calendar) throws {
        if kind == .rough || kind == .review, let session {
            guard let s = course.sessions.first(where: { $0.id == session }) else {
                throw ActionError.notFound(String(localized: .errorNotFoundSession))
            }
            if s.isCancelled { throw ActionError.rule(String(localized: .errorNoteCancelledSession)) }
            if let other = s.note(of: kind), other != meta.id {
                let name = course.title(of: s, calendar: calendar)
                throw ActionError.rule(
                    String(localized: kind == .rough ? .errorNoteSessionHasRough(name) : .errorNoteSessionHasReview(name)))
            }
        }
        if kind == .examSummary, let exam, !course.exams.contains(where: { $0.id == exam }) {
            throw ActionError.notFound(String(localized: .errorNotFoundExam))
        }
        if kind == .unit, let u = units.first(where: { u in !course.units.contains { $0.id == u } }) {
            throw ActionError.notFound(String(localized: .errorNotFoundUnitId("\(u)")))
        }
        meta.kind = kind
        meta.sessionId = kind == .rough || kind == .review ? session : nil
        meta.examId = kind == .examSummary ? exam : nil
        meta.unitIds = kind == .unit ? units : []
    }
}
