import FolioCore
import Foundation

// 시험에서 거꾸로 공부 계획을 짠다(#573 "시험에서 거꾸로 짠 계획"). 공부일이 바뀔 때마다 지금 상태로 다시 짜고,
// 사용자가 고친 항목은 그대로 둔다.
public enum ExamPlanner {
    public struct UnitInput: Sendable, Equatable {
        public var id: UUID
        public var weight: Double
        public var pages: [ProblemPage]

        public init(id: UUID, weight: Double, pages: [ProblemPage] = []) {
            self.id = id
            self.weight = weight
            self.pages = pages
        }
    }

    // 한 단원이 받는 자리는 둘까지다. 약한 단원만 하루 더 받는다.
    static let maxSeats = 2
    static let extraWeight = 0.5

    public static func plan(
        current: [ExamPlanItem], units: [UnitInput], today: LocalDate, examDay: LocalDate, finalDays: Int,
        isDone: (ExamPlanItem) -> Bool
    ) -> [ExamPlanItem] {
        let kept = current.filter { $0.isEdited || $0.isRemoved || ($0.day < today && isDone($0)) }
        let removed = Set(current.filter(\.isRemoved).map(\.target))
        let pinned = current.filter { $0.isEdited && !$0.isRemoved }
        let carried = Set(
            current.filter { !$0.isEdited && !$0.isRemoved && $0.day < today && !isDone($0) && $0.target.kind == .unit }
                .compactMap(\.target.id))

        let n = today.days(until: examDay)
        guard n > 0 else { return kept }
        var out = kept

        let finals = min(max(finalDays, 0), max(0, n - 1))
        let finalKinds: [ExamPlanTarget.Kind] = [.wrong, .mock, .mixed]
        for i in 0..<finals {
            let target = ExamPlanTarget(kind: finalKinds[i])
            guard !removed.contains(target), !pinned.contains(where: { $0.target == target }) else { continue }
            out.append(ExamPlanItem(day: examDay.adding(days: -(i + 1)), target: target))
        }

        let unitDays = n - finals
        let open = units.filter { !removed.contains(.unit($0.id)) }
        let needed = open.filter { u in !pinned.contains { $0.target == .unit(u.id) } }
        let seats = self.seats(needed, days: unitDays)
        // 옮긴 단원을 앞에 두어 오늘 하게 한다. 그다음은 범위 순서이고, 두 번째 자리는 모든 단원이 한 번씩 나온 뒤에 온다.
        let order = needed.filter { carried.contains($0.id) } + needed.filter { !carried.contains($0.id) }
        var sequence: [(UnitInput, first: Bool)] = order.map { ($0, true) }
        for round in 1..<maxSeats {
            sequence += order.filter { (seats[$0.id] ?? 1) > round }.map { ($0, false) }
        }
        let total = max(sequence.count, 1)
        for (i, (unit, first)) in sequence.enumerated() {
            let day = today.adding(days: i * unitDays / total)
            out.append(
                ExamPlanItem(
                    day: day, target: .unit(unit.id), carried: first && carried.contains(unit.id) ? true : nil,
                    pages: first && !unit.pages.isEmpty ? unit.pages : nil))
        }
        return out.sorted { $0.day < $1.day }
    }

    // 자리 수를 무게로 나눈다(D'Hondt). 무게가 큰 단원이 자리를 먼저 받으므로, 준비가 낮은 단원은 높은 단원보다 자리를
    // 적게 받지 않는다.
    static func seats(_ units: [UnitInput], days: Int) -> [UUID: Int] {
        var seats = Dictionary(keepingFirst: units.map { ($0.id, 1) })
        var extra = max(0, days - units.count)
        while extra > 0 {
            let pick = units.enumerated()
                .filter { (seats[$0.element.id] ?? 1) < maxSeats && $0.element.weight >= extraWeight }
                .max { a, b in
                    let qa = a.element.weight / Double((seats[a.element.id] ?? 1) + 1)
                    let qb = b.element.weight / Double((seats[b.element.id] ?? 1) + 1)
                    return qa != qb ? qa < qb : a.offset > b.offset
                }
            guard let pick else { break }
            seats[pick.element.id, default: 1] += 1
            extra -= 1
        }
        return seats
    }
}
