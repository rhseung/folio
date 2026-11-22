import FolioCore
import Foundation

public enum ExamPlan {
    public struct DayItem: Sendable, Equatable {
        public var courseId: UUID
        public var exam: Exam
        public var item: ExamPlanItem
    }

    // 이벤트는 여러 기기의 로그에서 순서 없이 들어온다.
    public static func done(_ events: [(at: Date, event: PlanCheckEvent)]) -> Set<UUID> {
        var latest: [UUID: (at: Date, done: Bool)] = [:]
        for (at, e) in events where latest[e.itemId].map({ at >= $0.at }) ?? true {
            latest[e.itemId] = (at, e.done)
        }
        return Set(latest.filter(\.value.done).keys)
    }

    public static func items(on day: LocalDate, courses: [CourseFile]) -> [DayItem] {
        courses.flatMap { file in
            file.exams.flatMap { exam in
                exam.plan.filter { $0.day == day && !$0.isRemoved }.map { DayItem(courseId: file.course.id, exam: exam, item: $0) }
            }
        }
        .sorted { ($0.exam.start ?? .distantFuture) < ($1.exam.start ?? .distantFuture) }
    }
}

extension CourseStudy {
    // 항목은 저절로 체크된다. 손으로 체크한 것도 체크다. 섞어 풀기와 모의시험은 그 풀기를 끝낼 때 체크 기록을 남긴다.
    public func isDone(_ item: ExamPlanItem, in exam: Exam) -> Bool {
        if manualChecks.contains(item.id) { return true }
        switch item.target.kind {
        case .unit:
            // 묶음 항목은 안의 단원이 모두 다 함이어야 체크된다.
            let units = item.target.units.compactMap { id in file.units.first { $0.id == id } }
            return !units.isEmpty && units.allSatisfy(\.isDone)
        case .problems:
            let records =
                item.target.problemIds.map { ids in ids.compactMap { problems[$0] } }
                ?? item.target.id.map { problems(inSet: $0) } ?? []
            return !records.isEmpty && records.allSatisfy(\.solved)
        case .wrong:
            // 남은 오답이 없다는 것은 그날까지 바뀔 수 있는 상태라, 오지 않은 날의 항목은 저절로 체크하지 않는다.
            guard item.day <= today else { return false }
            let left = wrongLeft(in: exam)
            return left.problems == 0 && left.cards == 0
        case .mixed, .mock, .custom:
            return false
        }
    }

    // 시험 범위에 남은 오답 문제와 모르는 카드 수다. 오답 항목의 체크와 화면의 세부 줄이 같은 수를 쓴다.
    public func wrongLeft(in exam: Exam) -> (problems: Int, cards: Int) {
        let scope = Set(file.scope(of: exam))
        return (
            allProblems.filter { $0.status.needsWork && !scope.isDisjoint(with: $0.problem.unitIds) }.count,
            allCards.filter { $0.status.needsWork && scope.contains($0.card.unitId) }.count
        )
    }

    // 부모와 자식이 함께 범위에 있으면 자식만 넣는다. 부모 단원을 공부하는 일은 자식 단원을 공부하는 일이라, 둘을 따로 넣으면 같은 내용이
    // 계획에 두 번 나온다. 범위는 그대로 둔다.
    public func planInputs(for exam: Exam) -> [ExamPlanner.UnitInput] {
        UnitTree.deepest(file.scopeUnits(of: exam), in: file.units).map { u in
            let r = readiness(of: u.id)
            return ExamPlanner.UnitInput(id: u.id, weight: r.planWeight, pages: r.conceptPages)
        }
    }

    public func replan(_ exam: Exam, calendar: Calendar, settings: Settings) -> [ExamPlanItem]? {
        guard let start = exam.start else { return nil }
        let examDay = settings.studyDay(of: start, calendar: calendar)
        return ExamPlanner.plan(
            current: exam.plan, units: planInputs(for: exam), today: today, examDay: examDay, finalDays: self.settings.finalDays,
            dayItems: self.settings.planDayItems, isDone: { isDone($0, in: exam) })
    }
}

extension CourseFile {
    // 단원이나 문제 묶음을 지우면 그것을 가리키는 계획 항목도 지워진다(`course-rules.swift`의 `.cascade`). 사용자가 쓴
    // 항목은 할 일의 글을 잃지 않도록 지우기 전에 대상 없는 항목으로 바꿔 남긴다.
    public mutating func keepWrittenPlanItems(pointingTo target: UUID) {
        for e in exams.indices {
            for i in exams[e].plan.indices {
                let item = exams[e].plan[i]
                guard item.isEdited, !item.isRemoved, item.target.id == target,
                    item.target.kind == .unit || item.target.kind == .problems
                else { continue }
                exams[e].plan[i].title = title(of: item)
                exams[e].plan[i].target = ExamPlanTarget(kind: .custom)
            }
        }
    }

    // 앱이 짠 항목은 제목을 저장하지 않고 대상에서 이름을 만든다. 단원 이름을 바꾸면 계획에도 바로 보이게 하기 위해서다.
    public func title(of item: ExamPlanItem) -> String {
        if !item.title.isEmpty { return item.title }
        switch item.target.kind {
        case .unit:
            return unitsTitle(item.target.units)
        case .problems:
            let set = item.target.id.flatMap { id in problemSets.first { $0.id == id } }
            let count = item.target.problemIds?.count
            switch (set, count) {
            case (let s?, let n?): return String(localized: .examPlanTitleSomeProblems(s.title, n))
            case (let s?, nil): return s.title
            default: return String(localized: .examPlanTitleProblems)
            }
        case .mixed: return String(localized: .examPlanTitleMixed)
        case .mock: return String(localized: .examPlanTitleMock)
        case .wrong: return String(localized: .examPlanTitleWrong)
        case .custom: return item.title
        }
    }

    // 묶음 항목은 단원 이름을 모두 이으면 무엇을 하는 날인지 읽히지 않는다. 한 부모의 단원이면 부모 이름으로, 아니면 첫 단원과 나머지
    // 개수로 부른다. 둘까지는 이어도 짧으므로 잇는다.
    func unitsTitle(_ ids: [UUID]) -> String {
        let bundled = ids.compactMap { id in units.first { $0.id == id } }
        guard let first = bundled.first else { return String(localized: .examPlanTitleUnit) }
        if bundled.count == 1 { return first.title }
        let parents = Set(bundled.map { UnitTree.parent(of: $0, in: units) })
        if parents.count == 1, let parentId = parents.first ?? nil, let parent = units.first(where: { $0.id == parentId }) {
            let siblings = units.filter { UnitTree.parent(of: $0, in: units) == parentId }
            if Set(siblings.map(\.id)) == Set(bundled.map(\.id)) { return parent.title }
            return String(localized: .examPlanTitleUnitsIn(parent.title, bundled.count))
        }
        if bundled.count == 2 { return bundled.map(\.title).joined(separator: ", ") }
        return String(localized: .examPlanTitleUnitsMore(first.title, bundled.count - 1))
    }
}
