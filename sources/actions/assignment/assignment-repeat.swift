import FolioDomain
import FolioStorage
import Foundation

func repeatEnd(_ ctx: ActionContext, course: UUID) throws -> Date? {
    try ctx.semester(of: ctx.file(course).course)?.end?.date(in: ctx.calendar)
        .flatMap { ctx.calendar.date(byAdding: .day, value: 1, to: $0) }?.addingTimeInterval(-1)
}

extension CourseFile {
    mutating func scoredAssignment(_ id: UUID, until end: Date?, _ ctx: ActionContext) {
        markGraded(id, device: ctx.device, now: ctx.now)
        continueRepeating(id, until: end, calendar: ctx.calendar, device: ctx.device, now: ctx.now)
    }
}
