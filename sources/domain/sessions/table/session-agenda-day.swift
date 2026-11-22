import FolioCore
import Foundation

// 좁은 폭의 회차 목록에서 날짜 타일 하나다. 주차 머리 아래에 일정이 있는 날만 날짜 순으로 쌓는다.
public struct SessionAgendaDay: Sendable, Identifiable {
    public let day: LocalDate
    public let isToday: Bool
    // 주가 두 달에 걸치면 뒤 달의 첫 타일 위에만 그 달을 붙인다. 앞 달은 주차 머리의 구간이 알린다.
    public let month: Int?
    public let entries: [SessionTableEntry]
    public var id: LocalDate { day }

    static func days(_ entries: [SessionTableEntry], weekStart: LocalDate, today: LocalDate) -> [SessionAgendaDay] {
        var marked = false
        return Dictionary(grouping: entries, by: \.day).sorted { $0.key < $1.key }.map { day, entries in
            let turns = !marked && day.month != weekStart.month
            if turns { marked = true }
            return SessionAgendaDay(
                day: day, isToday: day == today, month: turns ? day.month : nil, entries: SessionTable.ordered(entries))
        }
    }
}
