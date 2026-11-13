import FolioDomain
import Foundation

extension Workspace {
    var today: LocalDate { settings.studyDay(of: now, calendar: calendar) }

    func isStudyToday(_ date: Date) -> Bool { settings.studyDay(of: date, calendar: calendar) == today }

    // 하루 경계가 아직 남았을 때 D-day가 자정에 바뀌지 않도록 공부일로 센다.
    func days(to date: Date) -> Int { today.days(until: LocalDate(date, in: calendar)) }
}
