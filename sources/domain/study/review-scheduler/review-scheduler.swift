import Foundation

public enum ReviewScheduler {
    public static func state(of input: UnitReviewInput, settings: ReviewSettings, today: LocalDate) -> ReviewState {
        let steps = settings.intervals
        let last = steps.count - 1
        var step = 0
        var passesAtLast = 0
        var settled = false
        var due =
            input.needsReviewNote ? input.startDay : schedule(from: input.startDay, interval: steps[0], input: input, settings: settings)

        enum Happening { case review(ReviewResult), wrongCard }
        let timeline = (input.reviews.map { ($0.day, Happening.review($0.result)) } + input.wrongCardDays.map { ($0, Happening.wrongCard) })
            .filter { $0.0 >= input.startDay }
            .sorted { $0.0 < $1.0 }

        for (day, happening) in timeline {
            switch happening {
            case .review(let result):
                if step == last, result == .good || result == .easy { passesAtLast += 1 }
                step =
                    switch result {
                    case .again: 0
                    case .hard, .skip: step
                    case .good: min(step + 1, last)
                    case .easy: min(step + 2, last)
                    }
                if result == .again { passesAtLast = 0 }
                if result == .skip { passesAtLast = max(passesAtLast, settings.settleAfterPasses) }
                settled = passesAtLast >= settings.settleAfterPasses
                due = schedule(from: day, interval: steps[step], input: input, settings: settings)
            case .wrongCard:
                step = max(0, step - 1)
                passesAtLast = 0
                settled = false
                due = day.adding(days: 1)
            }
        }

        let writeNote = input.needsReviewNote && input.reviews.isEmpty
        if settled && !input.inExamPlan {
            return ReviewState(unitId: input.unitId, step: step, due: nil, settled: true, writeNoteFirst: false)
        }
        return ReviewState(unitId: input.unitId, step: step, due: due, settled: settled, writeNoteFirst: writeNote)
    }

    static func schedule(from day: LocalDate, interval: Int, input: UnitReviewInput, settings: ReviewSettings) -> LocalDate {
        var interval = interval
        if let exam = input.examDays.filter({ $0 > day }).min() {
            let left = day.days(until: exam)
            if left <= settings.examWindowDays { interval = min(interval, max(1, left / 2)) }
            interval = min(interval, max(1, left - 1))
        }
        return day.adding(days: interval)
    }

    // MARK: Today's queue

    public enum DeferReason: String, Sendable {
        case dailyLimit
    }

    public struct Item: Sendable, Equatable {
        public var unitId: UUID
        public var due: LocalDate
        public var overdueDays: Int
        public var priority: Double
        public var writeNoteFirst: Bool
        public var deferred: DeferReason?
    }

    public static func queue(_ states: [ReviewState], inputs: [UnitReviewInput], settings: ReviewSettings, today: LocalDate) -> [Item] {
        let byUnit = Dictionary(keepingFirst: inputs.map { ($0.unitId, $0) })
        let w = settings.weights
        var items = states.compactMap { state -> Item? in
            guard state.isDue(on: today), let due = state.due, let input = byUnit[state.unitId] else { return nil }
            let overdue = due.days(until: today)
            let interval = Double(settings.interval(atStep: state.step))
            var priority = w.overdue * Double(overdue) / interval
            if let exam = input.examDays.filter({ $0 >= today }).min() {
                priority += w.exam / Double(today.days(until: exam) + 1)
            }
            priority += w.quizMiss * (1 - (input.quizAccuracy ?? 1)) + w.openWrong * Double(input.openWrongCards)
            return Item(
                unitId: state.unitId, due: due, overdueDays: overdue, priority: priority, writeNoteFirst: state.writeNoteFirst,
                deferred: nil)
        }

        items.sort { ($0.priority, $1.due) > ($1.priority, $0.due) }
        if let limit = settings.dailyLimit, items.count > limit {
            for i in limit..<items.count { items[i].deferred = .dailyLimit }
        }
        return items
    }

    // 하루 한도는 모든 과목에 걸리므로, 한 과목의 목록은 따로 만들지 않고 이 큐를 거른다.
    public static func queue(
        courses: [(file: CourseFile, reviews: [(at: Date, event: ReviewEvent)])], settings: Settings,
        calendar: Calendar, now: Date
    ) -> [ReviewEntry] {
        let today = settings.studyDay(of: now, calendar: calendar)
        var inputs: [UnitReviewInput] = []
        var owners: [UUID: (UUID, String)] = [:]
        for (file, reviews) in courses {
            inputs += UnitReviewInput.all(for: file, reviews: reviews, settings: settings, calendar: calendar, now: now)
            for unit in file.units { owners[unit.id] = (file.course.id, unit.title) }
        }

        let states = inputs.map { state(of: $0, settings: settings.review, today: today) }
        return queue(states, inputs: inputs, settings: settings.review, today: today).compactMap { item in
            owners[item.unitId].map { ReviewEntry(item: item, courseId: $0.0, unitTitle: $0.1) }
        }
    }
}

extension LocalDate {
    // UTC에서는 모든 날이 24시간이므로 날짜 계산은 UTC로 한다.
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    public func adding(days: Int) -> LocalDate {
        LocalDate(Self.utc.date(byAdding: .day, value: days, to: date(in: Self.utc)!)!, in: Self.utc)
    }

    public func days(until other: LocalDate) -> Int {
        Self.utc.dateComponents([.day], from: date(in: Self.utc)!, to: other.date(in: Self.utc)!).day!
    }
}
