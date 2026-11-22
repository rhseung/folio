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
        current: [ExamPlanItem], units: [UnitInput], today: LocalDate, examDay: LocalDate, finalDays: Int, dayItems: Int = 2,
        isDone: (ExamPlanItem) -> Bool
    ) -> [ExamPlanItem] {
        // 오늘 끝낸 항목도 남긴다. 체크 기록이 항목 id를 가리키므로, 같은 날 다시 짜며 새로 만들면 체크가 사라진다.
        let finished = current.filter { !$0.isEdited && !$0.isRemoved && $0.day <= today && isDone($0) }
        let kept = current.filter { $0.isEdited || $0.isRemoved } + finished
        let removed = Set(current.filter(\.isRemoved).map(\.target))
        let removedUnits = Set(current.filter(\.isRemoved).flatMap(\.target.units))
        let pinned = current.filter { $0.isEdited && !$0.isRemoved }
        let pinnedUnits = Set(pinned.flatMap(\.target.units))
        let finishedToday = finished.filter { $0.day == today }
        let finishedTodayTargets = Set(finishedToday.map(\.target))
        let finishedTodayUnits = Set(finishedToday.flatMap(\.target.units))
        let carried = Set(
            current.filter { !$0.isEdited && !$0.isRemoved && $0.day < today && !isDone($0) && $0.target.kind == .unit }
                .flatMap(\.target.units))

        let n = today.days(until: examDay)
        guard n > 0 else { return kept }
        var out = kept

        let finalKinds: [ExamPlanTarget.Kind] = [.wrong, .mock, .mixed]
        // 설정 항목은 0~3일이지만 settings.json을 손으로 고치면 더 클 수 있다. 마지막 날의 할 일은 세 가지뿐이라 그 수에서 자른다.
        let finals = min(max(finalDays, 0), finalKinds.count, max(0, n - 1))
        for i in 0..<finals {
            let target = ExamPlanTarget(kind: finalKinds[i])
            guard !removed.contains(target), !finishedTodayTargets.contains(target), !pinned.contains(where: { $0.target == target }) else {
                continue
            }
            out.append(ExamPlanItem(day: examDay.adding(days: -(i + 1)), target: target))
        }

        let unitDays = n - finals
        let needed = units.filter { !removedUnits.contains($0.id) && !pinnedUnits.contains($0.id) }
        let seats = self.seats(needed, days: unitDays)
        // 옮긴 단원을 앞에 두어 오늘 하게 한다. 그다음은 범위 순서이고, 두 번째 자리는 모든 단원이 한 번씩 나온 뒤에 온다.
        let order = needed.filter { carried.contains($0.id) } + needed.filter { !carried.contains($0.id) }
        var sequence: [(UnitInput, first: Bool)] = order.map { ($0, true) }
        for round in 1..<maxSeats {
            sequence += order.filter { (seats[$0.id] ?? 1) > round }.map { ($0, false) }
        }
        let total = max(sequence.count, 1)
        var days: [Int: [(UnitInput, first: Bool)]] = [:]
        for (i, entry) in sequence.enumerated() {
            // 오늘 끝낸 단원은 남긴 항목이 첫 자리를 차지한다. 자리를 건너뛰기만 하므로 나머지 항목의 날은 바뀌지 않는다.
            if entry.first && finishedTodayUnits.contains(entry.0.id) { continue }
            days[i * unitDays / total, default: []].append(entry)
        }
        let cap = max(dayItems, 1)
        for (offset, entries) in days.sorted(by: { $0.key < $1.key }) {
            // 오늘 끝낸 항목도 오늘의 자리를 쓴다. 다 찼어도 남은 단원을 버릴 수 없으므로 한 항목은 둔다.
            let room = offset == 0 ? max(cap - finishedToday.count { $0.target.kind == .unit }, 1) : cap
            for chunk in chunks(entries, into: room) {
                let first = chunk.filter(\.first).map(\.0)
                let pages = first.flatMap(\.pages)
                out.append(
                    ExamPlanItem(
                        day: today.adding(days: offset), target: .units(chunk.map(\.0.id)),
                        carried: first.contains { carried.contains($0.id) } ? true : nil, pages: pages.isEmpty ? nil : pages))
            }
        }
        // 같은 날의 항목은 넣은 순서를 지킨다. 다시 짤 때마다 같은 날 안의 차례가 바뀌지 않게 한다.
        return out.enumerated().sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }.map(\.element)
    }

    // 하루 몫을 `count`개 이하의 연속한 묶음으로 고르게 나눈다. 앞 묶음이 하나씩 더 받는다.
    static func chunks<T>(_ items: [T], into count: Int) -> [[T]] {
        let parts = min(max(count, 1), items.count)
        guard parts > 0 else { return [] }
        let (size, extra) = (items.count / parts, items.count % parts)
        var out: [[T]] = [], start = 0
        for i in 0..<parts {
            let end = start + size + (i < extra ? 1 : 0)
            out.append(Array(items[start..<end]))
            start = end
        }
        return out
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
