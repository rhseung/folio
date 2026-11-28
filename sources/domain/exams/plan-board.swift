import FolioCore
import Foundation

// 계획 블록이 그리는 값이다. 오늘은 줄마다 단계를 보이고, 다음 날들은 날짜마다 묶어 접는다.
public struct PlanBoard: Sendable, Equatable {
    public struct Day: Sendable, Equatable, Identifiable {
        public var day: LocalDate
        public var rows: [PlanRow]
        public var id: LocalDate { day }

        public init(day: LocalDate, rows: [PlanRow]) {
            self.day = day
            self.rows = rows
        }
    }

    public var today: [PlanRow]
    public var next: [Day]

    public init(today: [PlanRow] = [], next: [Day] = []) {
        self.today = today
        self.next = next
    }

    public var isEmpty: Bool { today.isEmpty && next.isEmpty }

    public var notes: Int { today.count(where: \.kind.isNote) }
    public var wrong: Int { today.reduce(0) { if case .wrong(let progress) = $1.kind { $0 + progress.left } else { $0 } } }
    public var late: Int { today.count(where: \.isLate) }
    // 오늘 남은 줄이다. 어제 오답은 남은 오답이 있을 때만 줄이 되므로 언제나 남은 줄이다.
    public var left: Int { today.count { !$0.isDone } }

    public var nextNotes: Int { next.reduce(0) { n, day in n + day.rows.count(where: \.kind.isNote) } }
    public var nextMocks: Int { next.reduce(0) { n, day in n + day.rows.count { $0.kind == .mock } } }

    // 오늘 화면은 과목들의 계획을 한 블록에 모은다. 과목은 받은 차례를 지키고, 줄의 종류로만 다시 줄 세운다.
    public static func merged(_ boards: [PlanBoard]) -> PlanBoard {
        let today = boards.flatMap(\.today).enumerated().sorted { ($0.element.kind.rank, $0.offset) < ($1.element.kind.rank, $1.offset) }
        let days = Set(boards.flatMap { $0.next.map(\.day) }).sorted()
        return PlanBoard(
            today: today.map(\.element),
            next: days.map { day in Day(day: day, rows: boards.flatMap { $0.next.first { $0.day == day }?.rows ?? [] }) })
    }
}
