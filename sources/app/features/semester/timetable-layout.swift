import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

struct TimetableLayout {
    let slots: [(course: Course, time: ClassTime)]
    let days: [Int]
    let first: Int
    let last: Int

    init(courses: [Course]) {
        slots = courses.flatMap { c in c.schedule.map { (c, $0) } }
        days = Array(1...max(5, slots.map(\.time.weekday).max() ?? 5))
        first = (slots.map(\.time.startMinute).min() ?? 9 * 60) / 60
        last = ((slots.map(\.time.endMinute).max() ?? 18 * 60) + 59) / 60
    }

    func slots(on day: Int) -> [(course: Course, time: ClassTime)] { slots.filter { $0.time.weekday == day } }
}
