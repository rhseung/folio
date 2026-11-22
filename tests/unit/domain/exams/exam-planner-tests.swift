import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

struct ExamPlannerTests {
    static let today = LocalDate(Date(timeIntervalSince1970: 1_793_750_400), in: Calendar(identifier: .gregorian))
    static let ids = (0..<6).map { _ in UUID() }

    static func plan(
        _ current: [ExamPlanItem] = [], units: [ExamPlanner.UnitInput], days: Int, finalDays: Int = 3,
        done: Set<UUID> = []
    ) -> [ExamPlanItem] {
        ExamPlanner.plan(
            current: current, units: units, today: today, examDay: today.adding(days: days), finalDays: finalDays,
            isDone: { done.contains($0.id) })
    }

    @Test func theLastDaysAreMixedMockAndWrongAndUnitsComeFirst() {
        let units = [ExamPlanner.UnitInput(id: Self.ids[0], weight: 1), ExamPlanner.UnitInput(id: Self.ids[1], weight: 0.2)]
        let plan = Self.plan(units: units, days: 10)
        let finals = plan.filter { $0.target.kind != .unit }
        #expect(finals.map(\.target.kind) == [.mixed, .mock, .wrong])
        #expect(finals.map(\.day) == [7, 8, 9].map { Self.today.adding(days: $0) })
        // 남은 이레를 두 단원이 나눈다. 약한 첫 단원만 두 번째 자리를 받는다.
        let unitItems = plan.filter { $0.target.kind == .unit }
        #expect(unitItems.map(\.target.id) == [Self.ids[0], Self.ids[1], Self.ids[0]])
        #expect(unitItems.first?.day == Self.today)
    }

    @Test func fewerDaysThanTheFinalDaysLeaveTodayForUnits() {
        let plan = Self.plan(units: [ExamPlanner.UnitInput(id: Self.ids[0], weight: 1)], days: 2)
        #expect(plan.map(\.target.kind) == [.unit, .wrong])
        #expect(plan.map(\.day) == [Self.today, Self.today.adding(days: 1)])
    }

    @Test func replanningOnTheSameDayKeepsWhatWasFinishedToday() {
        let units = [ExamPlanner.UnitInput(id: Self.ids[0], weight: 1), ExamPlanner.UnitInput(id: Self.ids[1], weight: 1)]
        let first = Self.plan(units: units, days: 6)
        let todays = first.filter { $0.day == Self.today }
        #expect(todays.count == 1)
        let finished = Set(todays.map(\.id))

        let again = Self.plan(first, units: units, days: 6, done: finished)
        #expect(Set(again.map(\.id)).isSuperset(of: finished))
        // 끝낸 항목이 오늘 자리를 그대로 차지해서 나머지 항목의 날도 처음 짠 것과 같다.
        #expect(again.map(\.day) == first.map(\.day))
        #expect(again.map(\.target) == first.map(\.target))
    }

    @Test func itemsFinishedOnEarlierDaysStayAndUnfinishedOnesCarry() {
        let units = [ExamPlanner.UnitInput(id: Self.ids[0], weight: 1)]
        let yesterday = Self.today.adding(days: -1)
        let done = ExamPlanItem(day: yesterday, target: .unit(Self.ids[0]))
        let missed = ExamPlanItem(day: yesterday, target: .unit(Self.ids[1]))
        let plan = Self.plan(
            [done, missed], units: units + [ExamPlanner.UnitInput(id: Self.ids[1], weight: 0.1)], days: 6, done: [done.id])
        #expect(plan.contains { $0.id == done.id })
        #expect(!plan.contains { $0.id == missed.id })
        let carried = plan.first { $0.target == .unit(Self.ids[1]) && $0.day == Self.today }
        #expect(carried?.isCarried == true)
    }

    // 줄이기(shrink)가 배열을 짧게 만들 수 있어서 읽을 때 범위를 확인한다.
    static let weights = Gen.int(in: 0...20).array(of: 6)

    @Test func everyUnitGetsADayInsideTheWindowAndWeakerUnitsGetNoFewer() async {
        await propertyCheck(input: Gen.int(in: 1...6), Gen.int(in: 1...30), Gen.int(in: 0...4), Self.weights) { count, days, finals, w in
            let units = (0..<count).map { ExamPlanner.UnitInput(id: Self.ids[$0], weight: Double(w.indices.contains($0) ? w[$0] : 0) / 10) }
            let plan = Self.plan(units: units, days: days, finalDays: finals)
            let end = Self.today.adding(days: days)
            #expect(plan.allSatisfy { $0.day >= Self.today && $0.day < end })
            for u in units { #expect(plan.contains { $0.target == .unit(u.id) }) }
            let seats = Dictionary(grouping: plan.compactMap { $0.target.kind == .unit ? $0.target.id : nil }, by: { $0 }).mapValues(
                \.count)
            for a in units {
                for b in units where a.weight > b.weight {
                    #expect((seats[a.id] ?? 0) >= (seats[b.id] ?? 0))
                }
            }
        }
    }

    @Test func editedItemsSurviveReplanning() async {
        await propertyCheck(input: Gen.int(in: 1...6), Gen.int(in: 1...30), Gen.int(in: 0...29)) { count, days, at in
            let units = (0..<count).map { ExamPlanner.UnitInput(id: Self.ids[$0], weight: 1) }
            let mine = ExamPlanItem(day: Self.today.adding(days: at % days), target: .unit(Self.ids[0]), title: "내 복습", edited: true)
            let first = Self.plan([mine], units: units, days: days)
            let again = Self.plan(first, units: units, days: days)
            #expect(again.contains(mine))
        }
    }
}
