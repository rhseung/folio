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
            return item.target.id.flatMap { id in file.units.first { $0.id == id } }?.isDone ?? false
        case .problems:
            let records =
                item.target.problemIds.map { ids in ids.compactMap { problems[$0] } }
                ?? item.target.id.map { problems(inSet: $0) } ?? []
            return !records.isEmpty && records.allSatisfy(\.solved)
        case .wrong:
            let scope = Set(file.scope(of: exam))
            let problemsLeft = allProblems.contains { $0.status.needsWork && !scope.isDisjoint(with: $0.problem.unitIds) }
            let cardsLeft = allCards.contains { $0.status.needsWork && scope.contains($0.card.unitId) }
            return !problemsLeft && !cardsLeft
        case .mixed, .mock, .custom:
            return false
        }
    }

    public func planInputs(for exam: Exam) -> [ExamPlanner.UnitInput] {
        file.scopeUnits(of: exam).map { u in
            let r = readiness(of: u.id)
            return ExamPlanner.UnitInput(id: u.id, weight: r.planWeight, pages: r.conceptPages)
        }
    }

    public func replan(_ exam: Exam, calendar: Calendar, settings: Settings) -> [ExamPlanItem]? {
        guard let start = exam.start else { return nil }
        let examDay = settings.studyDay(of: start, calendar: calendar)
        return ExamPlanner.plan(
            current: exam.plan, units: planInputs(for: exam), today: today, examDay: examDay, finalDays: self.settings.finalDays,
            isDone: { isDone($0, in: exam) })
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
            return item.target.id.flatMap { id in units.first { $0.id == id }?.title } ?? String(localized: .examPlanTitleUnit)
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
}
