import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

struct ExamPlannerTests {
    static let today = day("2026-12-01")
    static let ids = (0..<16).map { _ in UUID() }

    static func day(_ text: String) -> LocalDate {
        guard let day = LocalDate(text) else { preconditionFailure(text) }
        return day
    }

    static func notes(_ count: Int, proofs: Set<Int> = [], missing: [UUID] = []) -> ExamPlanNotes {
        ExamPlanNotes(notes: (0..<count).map { ExamPlanNotes.Note(id: ids[$0], proof: proofs.contains($0)) }, missing: missing)
    }

    // 날은 오늘에서 센 날 수다. 시험은 따로 주지 않으면 끝낼 날의 다음 날이다.
    static func plan(
        _ current: [ExamPlanItem] = [], notes: ExamPlanNotes, start: Int = 0, end: Int, exam: Int? = nil,
        after: ExamPlanPeriod.After = .empty, mocks: Int = 0, done: Set<UUID> = []
    ) -> [ExamPlanItem] {
        ExamPlanner.plan(
            current: current, notes: notes,
            period: ExamPlanPeriod(start: today.adding(days: start), end: today.adding(days: end), after: after), mocks: mocks,
            today: today, examDay: today.adding(days: exam ?? end + 1), isDone: { done.contains($0.id) })
    }

    static func offsets(_ plan: [ExamPlanItem]) -> [Int] { plan.map { today.days(until: $0.day) } }

    @Test func threeNotesOverSixDaysTakeEveryOtherDay() {
        // 엿새에 노트 셋이면 차례 i의 날은 i×6÷3이라 0, 2, 4번째 날이다. 첫 노트만 정리 블록이 있어 증명을 받는다.
        let plan = Self.plan(notes: Self.notes(3, proofs: [0]), end: 5)
        #expect(
            plan.map(\.target) == [
                .note(Self.ids[0], .read), .note(Self.ids[0], .proof), .note(Self.ids[0], .solve),
                .note(Self.ids[1], .read), .note(Self.ids[1], .solve), .note(Self.ids[2], .read), .note(Self.ids[2], .solve),
            ])
        #expect(Self.offsets(plan) == [0, 0, 0, 2, 2, 4, 4])
        #expect(plan.allSatisfy { !$0.isEdited && $0.postponedFrom == nil })
    }

    @Test func moreNotesThanDaysShareTheEarlyDays() {
        // 나흘에 노트 다섯이면 i×4÷5라 0, 0, 1, 2, 3이다. 단계는 노트마다 둘이다.
        let plan = Self.plan(notes: Self.notes(5), end: 3)
        #expect(Self.offsets(plan.filter { $0.target.stage == .read }) == [0, 0, 1, 2, 3])
        #expect(plan.count == 10)
    }

    @Test func unitsWithoutANoteComeFirstOnTheFirstDay() {
        let plan = Self.plan(notes: Self.notes(2, missing: [Self.ids[10], Self.ids[11]]), start: 2, end: 5)
        #expect(plan.prefix(2).map(\.target) == [.makeNote(Self.ids[10]), .makeNote(Self.ids[11])])
        // 기간이 모레 시작하므로 노트 만들기와 첫 노트가 모두 모레다.
        #expect(Self.offsets(plan) == [2, 2, 2, 2, 4, 4])
    }

    @Test func aPeriodThatAlreadyStartedUsesItsRemainingDays() {
        // 그저께 시작해 내일 끝나는 기간에는 오늘과 내일만 남았다. 노트 넷은 i×2÷4라 0, 0, 1, 1이다.
        let plan = Self.plan(notes: Self.notes(4), start: -2, end: 1)
        #expect(Self.offsets(plan.filter { $0.target.stage == .read }) == [0, 0, 1, 1])
    }

    @Test func aPeriodThatIsOverPutsEverythingOnItsLastDay() {
        let plan = Self.plan(notes: Self.notes(2, missing: [Self.ids[10]]), start: -5, end: -1, exam: 3)
        #expect(Self.offsets(plan) == [-1, -1, -1, -1, -1])
    }

    @Test func mockExamsFillTheDaysAfterThePeriodOneADay() {
        // 끝낼 날이 모레이고 시험이 이레 뒤면 그 사이는 3, 4, 5, 6번째 날이다. 족보가 셋이면 사흘만 쓴다.
        let three = Self.plan(notes: Self.notes(1), end: 2, exam: 7, after: .mock, mocks: 3)
        #expect(Self.offsets(three.filter { $0.target == .mock }) == [3, 4, 5])
        let many = Self.plan(notes: Self.notes(1), end: 2, exam: 7, after: .mock, mocks: 10)
        #expect(Self.offsets(many.filter { $0.target == .mock }) == [3, 4, 5, 6])
        #expect(!Self.plan(notes: Self.notes(1), end: 2, exam: 7, mocks: 3).contains { $0.target == .mock })
    }

    @Test func mockExamsStartTodayWhenThePeriodIsOver() {
        let plan = Self.plan(notes: Self.notes(0), start: -4, end: -2, exam: 2, after: .mock, mocks: 5)
        #expect(Self.offsets(plan) == [0, 1])
    }

    @Test func replanningKeepsFinishedAndEditedItemsAndTheirIds() {
        let first = Self.plan(notes: Self.notes(3, proofs: [0]), end: 5)
        let read = first[0]
        var moved = first[4]
        moved.day = Self.today.adding(days: 5)
        moved.edited = true
        var current = first
        current[4] = moved
        // 노트 하나가 늘어 다시 놓는다. 끝낸 정독과 옮긴 문제풀이는 그대로이고, 나머지는 노트 넷으로 다시 나뉜다.
        let again = Self.plan(current, notes: Self.notes(4, proofs: [0]), end: 5, done: [read.id])
        #expect(again.contains(read) && again.contains(moved))
        #expect(again.count == first.count + 2)
        // 첫 노트는 정독을 뺀 두 단계가 남았다. 노트 넷이 엿새에 0, 1, 3, 4번째 날을 받는다.
        let reads = again.filter { $0.target.stage == .read && $0.id != read.id }
        #expect(Self.offsets(reads) == [1, 3, 4])
        #expect(Self.offsets(again.filter { $0.target.id == Self.ids[0] && $0.target.stage != .read }) == [0, 0])
        // 다시 놓은 항목도 id를 지킨다.
        #expect(Set(first.map(\.id)).isSubset(of: Set(again.map(\.id))))
    }

    @Test func replanningWithTheSameInputsChangesNothing() {
        let first = Self.plan(notes: Self.notes(4, proofs: [1], missing: [Self.ids[9]]), end: 6, exam: 10, after: .mock, mocks: 2)
        #expect(
            Self.plan(first, notes: Self.notes(4, proofs: [1], missing: [Self.ids[9]]), end: 6, exam: 10, after: .mock, mocks: 2) == first)
    }

    @Test func removedItemsDoNotComeBack() throws {
        var first = Self.plan(notes: Self.notes(2), end: 3, exam: 6, after: .mock, mocks: 1)
        let solve = try #require(first.firstIndex { $0.target == .note(Self.ids[1], .solve) })
        let mock = try #require(first.firstIndex { $0.target == .mock })
        first[solve].removed = true
        first[mock].removed = true
        let again = Self.plan(first, notes: Self.notes(2), end: 3, exam: 6, after: .mock, mocks: 1)
        #expect(
            again.filter { !$0.isRemoved }.map(\.target) == [
                .note(Self.ids[0], .read), .note(Self.ids[0], .solve), .note(Self.ids[1], .read),
            ])
    }

    @Test func itemsOfNotesThatLeftTheListAreDroppedUnlessFinished() throws {
        let first = Self.plan(notes: Self.notes(2, proofs: [0], missing: [Self.ids[9]]), end: 3)
        var pinned = first
        for i in pinned.indices { pinned[i].edited = true }
        let finished = try #require(first.first { $0.target == .note(Self.ids[1], .read) })
        // 둘째 노트가 목록에서 빠지고, 단원에 노트가 생기고, 첫 노트의 정리 블록이 없어졌다.
        let again = Self.plan(pinned, notes: Self.notes(1), end: 3, done: [finished.id])
        #expect(Set(again.map(\.target)) == [.note(Self.ids[0], .read), .note(Self.ids[0], .solve), .note(Self.ids[1], .read)])
    }

    @Test func writtenTasksAlwaysStay() {
        let mine = ExamPlanItem(day: Self.today.adding(days: 9), target: .custom, title: "교재 3장")
        #expect(Self.plan([mine], notes: Self.notes(1), end: 2).contains(mine))
    }

    static let flags = Gen.bool.array(of: 12)

    @Test func everyStageOfEveryNoteIsPlacedOnceInsideThePeriodAndInOrder() async {
        await propertyCheck(
            input: Gen.int(in: 0...12), Gen.int(in: -5...10), Gen.int(in: 0...20), Gen.int(in: 0...3), Self.flags
        ) { count, start, length, missing, proofs in
            let hasProof = Set((0..<count).filter { proofs.indices.contains($0) && proofs[$0] })
            let notes = Self.notes(count, proofs: hasProof, missing: Array(Self.ids[12..<(12 + missing)]))
            let end = start + length
            let plan = Self.plan(notes: notes, start: start, end: end)
            let period = Self.today.adding(days: start)...Self.today.adding(days: end)
            #expect(plan.allSatisfy { period.contains($0.day) })
            // 남은 날이 있으면 지난 날에는 놓지 않는다.
            if end >= 0 { #expect(plan.allSatisfy { $0.day >= Self.today }) }
            var expected: [ExamPlanTarget] = notes.missing.map { .makeNote($0) }
            for note in notes.notes { expected += PlanStage.stages(proof: note.proof).map { .note(note.id, $0) } }
            #expect(plan.map(\.target) == expected)
            // 배열이 날짜순이고 대상이 노트 순, 단계 순이므로 뒤 노트가 앞 노트보다 이른 날에 오지 않는다.
            #expect(plan.map(\.day) == plan.map(\.day).sorted())
            for note in notes.notes { #expect(Set(plan.filter { $0.target.id == note.id }.map(\.day)).count == 1) }
        }
    }

    @Test func itemsTheUserMovedSurviveReplanning() async {
        await propertyCheck(input: Gen.int(in: 1...8), Gen.int(in: 1...20), Gen.int(in: 0...40), Gen.int(in: -3...25)) {
            count, length, pick, to in
            let notes = Self.notes(count, proofs: [0])
            var current = Self.plan(notes: notes, end: length)
            let i = pick % current.count
            current[i].day = Self.today.adding(days: to)
            current[i].edited = true
            let moved = current[i]
            // 노트 목록이 달라져 다시 놓아도 옮긴 항목은 그 날에 있다.
            let again = Self.plan(current, notes: Self.notes(count + 1, proofs: [0]), end: length)
            #expect(again.contains(moved))
            #expect(again.count { $0.target == moved.target } == 1)
        }
    }

    @Test func postponingMovesOnlyTheItemsItIsGiven() async {
        await propertyCheck(input: Gen.int(in: 1...8), Gen.int(in: 0...20), Gen.int(in: 0...40), Gen.int(in: -3...6)) {
            count, length, pick, shift in
            var exam = Exam(device: UUID(), at: Date(timeIntervalSince1970: 0), title: "기말고사")
            exam.plan = Self.plan(notes: Self.notes(count, proofs: [0]), end: length)
            let before = exam.plan
            let picked = before[pick % before.count]
            // 오늘이 계획을 놓은 날에서 며칠 지났든, 미룬 항목은 그날과 오늘 가운데 늦은 날의 다음 날로 간다.
            let today = Self.today.adding(days: shift)
            exam.postponePlan([picked.id], today: today)
            for (old, new) in zip(before, exam.plan) where old.id != picked.id { #expect(old == new) }
            let moved = exam.plan.first { $0.id == picked.id }
            #expect(moved?.day == max(picked.day, today).adding(days: 1))
            #expect(moved?.postponedFrom == picked.day && moved?.isEdited == true)
        }
    }
}
