import Foundation

public struct UnitReviewInput: Sendable {
    public var unitId: UUID
    public var startDay: LocalDate
    public var needsReviewNote: Bool
    public var reviews: [(day: LocalDate, result: ReviewResult)]
    public var wrongCardDays: [LocalDate]
    public var examDays: [LocalDate]
    public var inExamPlan: Bool
    public var quizAccuracy: Double?
    public var openWrongCards: Int

    public init(
        unitId: UUID, startDay: LocalDate, needsReviewNote: Bool = false, reviews: [(day: LocalDate, result: ReviewResult)] = [],
        wrongCardDays: [LocalDate] = [], examDays: [LocalDate] = [], inExamPlan: Bool = false,
        quizAccuracy: Double? = nil, openWrongCards: Int = 0
    ) {
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

extension UnitReviewInput {
    // shortcut: 복습 노트를 만든 날이 아니라 회차 날짜부터 센다. 노트가 만든 날을 기록하게 되면 노트 파일의 생성일을 쓴다.
    public static func all(
        for file: CourseFile, reviews: [(at: Date, event: ReviewEvent)], settings: Settings, calendar: Calendar, now: Date
    ) -> [UnitReviewInput] {
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
                reviews: reviews.filter { $0.event.unitId == unit.id }.map {
                    (settings.studyDay(of: $0.at, calendar: calendar), $0.event.result)
                },
                examDays: examDays
            )
        }
    }
}
