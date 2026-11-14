import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

struct Attempt<Event: LogEvent> {
    var at: Date
    var day: LocalDate
    var event: Event
}
