import FolioDomain
import FolioStorage
import Foundation

extension CourseFile {
    mutating func set(
        session id: UUID, date: Patch<Date>, end: Patch<Date?>, link: Patch<String?>, kind: Patch<Session.Kind>,
        skipsReview: Patch<Bool>, reviewUnfinished: Patch<Bool>, termStart: LocalDate?, calendar: Calendar
    ) throws {
        if let date = date.value { reschedule(id, to: date, termStart: termStart, calendar: calendar) }
        let schedule = course.schedule
        try update(\.sessions, id) { s in
            if let end = end.value { s.setEnd(end, schedule: schedule, calendar: calendar) }
            if let link = link.value { s.link = OnlineLink.stored(link) }
            kind.apply(&s.kind)
            skipsReview.apply(&s.skipsReview)
            reviewUnfinished.apply(&s.reviewNoteUnfinished)
        }
        if let unfinished = reviewUnfinished.value, let note = sessions.first(where: { $0.id == id })?.reviewNoteId {
            setReviewNoteUnfinished(note, unfinished)
        }
        if kind.value == .cancelled { attendance.removeAll { $0.sessionId == id } }
    }
}
