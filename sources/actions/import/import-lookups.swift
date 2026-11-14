import FolioDomain
import FolioStorage
import Foundation

func courseIDs(_ ctx: ActionContext) throws -> [String: UUID] {
    Dictionary(
        try ctx.gist.courseStores().map { ($0.url.lastPathComponent, try $0.load().model.course.id) }, uniquingKeysWith: { a, _ in a })
}

func shortTime(_ d: Date?) -> String { d?.formatted(.dateTime.month().day().weekday().hour().minute()) ?? "-" }
func weekdayTime(_ d: Date) -> String { d.formatted(.dateTime.weekday().hour().minute()) }
