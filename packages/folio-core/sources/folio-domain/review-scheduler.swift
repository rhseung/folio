import Foundation

public enum ReviewResult: String, Codable, Sendable, CaseIterable {
    case again, hard, good, easy
    /// Not needed (already studied, e.g. for a past exam): the unit settles until a wrong card or an exam plan brings it back.
    case skip
}

/// `review` log event (docs/SPEC.md "Event").
public struct ReviewEvent: LogEvent, Equatable {
    public static let type = "review"
    public var unitId: UUID
    public var result: ReviewResult
    public var seconds: Int

    public init(unitId: UUID, result: ReviewResult, seconds: Int) {
        self.unitId = unitId
        self.result = result
        self.seconds = seconds
    }
}

/// Everything the scheduler needs about one unit, already reduced to study days.
public struct UnitReviewInput: Sendable {
    public var unitId: UUID
    /// Day the cycle starts: the review note's creation day, or the last session's day when there is no review note.
    public var startDay: LocalDate
    /// No review note yet: the first task is writing it, due on `startDay`.
    public var needsReviewNote: Bool
    public var reviews: [(day: LocalDate, result: ReviewResult)]
    /// Days a quiz card of this unit was answered wrong.
    public var wrongCardDays: [LocalDate]
    /// Days of upcoming exams whose scope includes the unit.
    public var examDays: [LocalDate]
    /// Settled units come back only while an exam plan covers them.
    public var inExamPlan: Bool
    public var quizAccuracy: Double?
    public var openWrongCards: Int

    public init(unitId: UUID, startDay: LocalDate, needsReviewNote: Bool = false, reviews: [(day: LocalDate, result: ReviewResult)] = [],
                wrongCardDays: [LocalDate] = [], examDays: [LocalDate] = [], inExamPlan: Bool = false,
                quizAccuracy: Double? = nil, openWrongCards: Int = 0) {
        self.unitId = unitId
        self.startDay = startDay
        self.needsReviewNote = needsReviewNote
        self.reviews = reviews
        self.wrongCardDays = wrongCardDays
        self.examDays = examDays
        self.inExamPlan = inExamPlan
        self.quizAccuracy = quizAccuracy
        self.openWrongCards = openWrongCards
    }
}

public struct ReviewState: Sendable, Equatable {
    public var unitId: UUID
    /// Index into the interval steps.
    public var step: Int
    public var due: LocalDate?
    public var settled: Bool
    public var writeNoteFirst: Bool

    public init(unitId: UUID, step: Int, due: LocalDate?, settled: Bool, writeNoteFirst: Bool) {
        self.unitId = unitId
        self.step = step
        self.due = due
        self.settled = settled
        self.writeNoteFirst = writeNoteFirst
    }
}

public enum ReviewScheduler {
    /// Replays reviews and wrong cards in day order (docs/SPEC.md "간격").
    public static func state(of input: UnitReviewInput, settings: ReviewSettings, today: LocalDate) -> ReviewState {
        let steps = settings.intervals
        let last = steps.count - 1
        var step = 0
        var passesAtLast = 0
        var settled = false
        var due = input.needsReviewNote ? input.startDay : schedule(from: input.startDay, interval: steps[0], input: input, settings: settings)

        enum Happening { case review(ReviewResult), wrongCard }
        let timeline = (input.reviews.map { ($0.day, Happening.review($0.result)) } + input.wrongCardDays.map { ($0, Happening.wrongCard) })
            .filter { $0.0 >= input.startDay }
            .sorted { $0.0 < $1.0 }

        for (day, happening) in timeline {
            switch happening {
            case .review(let result):
                if step == last, result == .good || result == .easy { passesAtLast += 1 }
                step = switch result {
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
                // A wrong card pulls the next review to tomorrow and drops a step.
                step = max(0, step - 1)
                passesAtLast = 0
                settled = false
                due = day.adding(days: 1)
            }
        }

        let writeNote = input.needsReviewNote && input.reviews.isEmpty
        if settled && !input.inExamPlan { return ReviewState(unitId: input.unitId, step: step, due: nil, settled: true, writeNoteFirst: false) }
        return ReviewState(unitId: input.unitId, step: step, due: due, settled: settled, writeNoteFirst: writeNote)
    }

    /// Next review after `day`, shortened before exams: never past the day before the next exam, and within
    /// the exam window at most half the days left.
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

    /// Units due today or earlier, highest priority first. Past the daily limit, the rest are marked deferred.
    public static func queue(_ states: [ReviewState], inputs: [UnitReviewInput], settings: ReviewSettings, today: LocalDate) -> [Item] {
        let byUnit = Dictionary(keepingFirst: inputs.map { ($0.unitId, $0) })
        let w = settings.weights
        var items = states.compactMap { state -> Item? in
            guard let due = state.due, due <= today, let input = byUnit[state.unitId] else { return nil }
            let overdue = due.days(until: today)
            let interval = Double(settings.interval(atStep: state.step))
            var priority = w.overdue * Double(overdue) / interval
            if let exam = input.examDays.filter({ $0 >= today }).min() {
                priority += w.exam / Double(today.days(until: exam) + 1)
            }
            priority += w.quizMiss * (1 - (input.quizAccuracy ?? 1)) + w.openWrong * Double(input.openWrongCards)
            return Item(unitId: state.unitId, due: due, overdueDays: overdue, priority: priority, writeNoteFirst: state.writeNoteFirst, deferred: nil)
        }
        items.sort { ($0.priority, $1.due) > ($1.priority, $0.due) }
        if let limit = settings.dailyLimit, items.count > limit {
            for i in limit..<items.count { items[i].deferred = .dailyLimit }
        }
        return items
    }

    /// Today's queue across `courses`, each with its review log. The daily limit spans all courses, so one course's
    /// list filters this queue rather than building its own.
    public static func queue(courses: [(file: CourseFile, reviews: [(at: Date, event: ReviewEvent)])], settings: Settings,
                             calendar: Calendar, now: Date) -> [ReviewEntry] {
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

public struct ReviewEntry: Sendable, Equatable {
    public var item: ReviewScheduler.Item
    public var courseId: UUID
    public var unitTitle: String
}

extension LocalDate {
    /// Day arithmetic in UTC, where every day has 24 hours.
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

extension UnitReviewInput {
    /// Scheduler input for every unit of a course. A unit's cycle starts from its latest session; without a review
    /// note on that session, writing the note comes first.
    // shortcut: starts from the session day, not the review note's creation day; use the note file's creation date once notes record it.
    public static func all(for file: CourseFile, reviews: [(at: Date, event: ReviewEvent)], settings: Settings, calendar: Calendar, now: Date) -> [UnitReviewInput] {
        guard file.course.reviews != false else { return [] }
        return file.units.compactMap { unit in
            let sessions = file.sessions.filter { unit.sessionIds.contains($0.id) && !$0.isCancelled && !$0.skipsReview && $0.date <= now }
            guard let last = sessions.max(by: { $0.date < $1.date }) else { return nil }
            let examDays = file.exams.filter { $0.scopeUnitIds.contains(unit.id) }.compactMap(\.start).filter { $0 > now }
                .map { LocalDate($0, in: calendar) }
            return UnitReviewInput(
                unitId: unit.id,
                startDay: settings.studyDay(of: last.date, calendar: calendar),
                needsReviewNote: last.reviewNoteId == nil || last.reviewNoteUnfinished,
                reviews: reviews.filter { $0.event.unitId == unit.id }.map { (settings.studyDay(of: $0.at, calendar: calendar), $0.event.result) },
                examDays: examDays
            )
        }
    }
}

public enum ReviewStreak {
    /// Study days in a row with a review, ending today. A today with nothing done yet keeps yesterday's run alive,
    /// so the count doesn't drop to zero every morning.
    public static func days(_ reviewDays: Set<LocalDate>, today: LocalDate) -> Int {
        var day = reviewDays.contains(today) ? today : today.adding(days: -1)
        var count = 0
        while reviewDays.contains(day) {
            count += 1
            day = day.adding(days: -1)
        }
        return count
    }
}
