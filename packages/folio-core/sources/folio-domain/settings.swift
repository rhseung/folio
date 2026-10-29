import Foundation

/// `GIST/.folio/settings.json`. Every user-tunable number lives here; the defaults below are the only place
/// they are written down.
public struct Settings: Codable, Sendable, Equatable {
    /// Minutes after midnight when "today" turns over (docs/SPEC.md "하루 경계"). 240 = 04:00.
    public var dayBoundaryMinutes: Int
    public var review: ReviewSettings
    /// "노트 작성 규칙", always sent to Claude with the course context (docs/SPEC.md "노트 템플릿").
    public var noteRules: String
    public var notifications: NotificationSettings
    public var backup: BackupSettings
    /// Section headings per `NoteKind` raw value; kinds left out use `NoteTemplate.defaultSections`.
    public var noteTemplates: [String: [String]]
    /// Math syntax for notes made in the app. Notes keep theirs in the frontmatter, so changing this touches no note.
    public var newNoteMath: MathSyntax
    public var sidebar: SidebarOrder

    public static let defaultNoteRules = """
    - 정의는 전제, 조건, 결론 순서로 쓴다.
    - 수학적 진술은 영어와 기호로, 설명은 한국어로 쓴다.
    - display 수식은 하나씩 나눠 쓴다.
    """

    public init(dayBoundaryMinutes: Int = 240, review: ReviewSettings = .init(), noteRules: String = Settings.defaultNoteRules,
                notifications: NotificationSettings = .init(), backup: BackupSettings = .init(), noteTemplates: [String: [String]] = [:],
                newNoteMath: MathSyntax = .asciimath, sidebar: SidebarOrder = .init()) {
        self.dayBoundaryMinutes = dayBoundaryMinutes
        self.review = review
        self.noteRules = noteRules
        self.notifications = notifications
        self.backup = backup
        self.noteTemplates = noteTemplates
        self.newNoteMath = newNoteMath
        self.sidebar = sidebar
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        dayBoundaryMinutes = try c.value(.dayBoundaryMinutes, or: d.dayBoundaryMinutes)
        review = try c.value(.review, or: d.review)
        noteRules = try c.value(.noteRules, or: d.noteRules)
        notifications = try c.value(.notifications, or: d.notifications)
        backup = try c.value(.backup, or: d.backup)
        noteTemplates = try c.value(.noteTemplates, or: d.noteTemplates)
        newNoteMath = try c.value(.newNoteMath, or: d.newNoteMath)
        sidebar = try c.value(.sidebar, or: d.sidebar)
    }

    /// Blank headings are rows the editor keeps while they're being typed; a note never gets them.
    public func noteSections(for kind: NoteKind) -> [String] {
        (noteTemplates[kind.rawValue] ?? NoteTemplate.defaultSections(for: kind)).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The study day `date` belongs to: work done at 02:00 counts for the previous day.
    public func studyDay(of date: Date, calendar: Calendar) -> LocalDate {
        LocalDate(calendar.date(byAdding: .minute, value: -dayBoundaryMinutes, to: date)!, in: calendar)
    }
}

public struct ReviewSettings: Codable, Sendable, Equatable {
    /// Days between reviews, step by step.
    public var intervals: [Int]
    /// Passes (good or easy) at the last step after which a unit is settled.
    public var settleAfterPasses: Int
    /// Reviews per day; the lowest-priority overflow moves to tomorrow. Nil means no limit.
    public var dailyLimit: Int?
    /// Within this many days before an exam, intervals are capped at half the days left.
    public var examWindowDays: Int
    /// Cards picked per review session.
    public var cardsPerReview: Int
    public var weights: PriorityWeights

    public init(intervals: [Int] = [1, 3, 7, 14, 30], settleAfterPasses: Int = 2, dailyLimit: Int? = nil,
                examWindowDays: Int = 7, cardsPerReview: Int = 5, weights: PriorityWeights = .init()) {
        self.intervals = intervals
        self.settleAfterPasses = settleAfterPasses
        self.dailyLimit = dailyLimit
        self.examWindowDays = examWindowDays
        self.cardsPerReview = cardsPerReview
        self.weights = weights
    }

    /// The interval at `step`; steps past the last keep the last interval.
    public func interval(atStep step: Int) -> Int { intervals[min(max(step, 0), intervals.count - 1)] }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReviewSettings()
        // Every step is indexed and divided by, so a hand-edited empty or non-positive list falls back to the default.
        let decoded = try c.decodeIfPresent([Int].self, forKey: .intervals)?.filter { $0 > 0 } ?? []
        intervals = decoded.isEmpty ? d.intervals : decoded
        settleAfterPasses = try c.decodeIfPresent(Int.self, forKey: .settleAfterPasses) ?? d.settleAfterPasses
        dailyLimit = try c.decodeIfPresent(Int.self, forKey: .dailyLimit)
        examWindowDays = try c.decodeIfPresent(Int.self, forKey: .examWindowDays) ?? d.examWindowDays
        cardsPerReview = try c.decodeIfPresent(Int.self, forKey: .cardsPerReview) ?? d.cardsPerReview
        weights = try c.decodeIfPresent(PriorityWeights.self, forKey: .weights) ?? d.weights
    }
}

/// Weights of the overdue-priority terms (docs/SPEC.md "밀린 복습의 우선순위").
public struct PriorityWeights: Codable, Sendable, Equatable {
    /// × (days overdue / current interval)
    public var overdue: Double
    /// × 1 / (days until the nearest exam that covers the unit + 1)
    public var exam: Double
    /// × (1 - recent quiz accuracy)
    public var quizMiss: Double
    /// × open wrong cards
    public var openWrong: Double

    public init(overdue: Double = 1, exam: Double = 3, quizMiss: Double = 1, openWrong: Double = 0.2) {
        self.overdue = overdue
        self.exam = exam
        self.quizMiss = quizMiss
        self.openWrong = openWrong
    }
}

/// docs/SPEC.md "알림". Times are minutes after midnight in real (clock) time.
public struct NotificationSettings: Codable, Sendable, Equatable {
    public var assignmentDue = true
    public var assignmentLeadHours = [24, 3]
    public var examDayBefore = true
    public var examDayBeforeMinute = 21 * 60
    public var examMorning = true
    public var examMorningMinute = 8 * 60
    public var dailyReview = true
    public var dailyReviewMinute = 9 * 60
    public var attendance = true

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        assignmentDue = try c.value(.assignmentDue, or: d.assignmentDue)
        assignmentLeadHours = try c.value(.assignmentLeadHours, or: d.assignmentLeadHours)
        examDayBefore = try c.value(.examDayBefore, or: d.examDayBefore)
        examDayBeforeMinute = try c.value(.examDayBeforeMinute, or: d.examDayBeforeMinute)
        examMorning = try c.value(.examMorning, or: d.examMorning)
        examMorningMinute = try c.value(.examMorningMinute, or: d.examMorningMinute)
        dailyReview = try c.value(.dailyReview, or: d.dailyReview)
        dailyReviewMinute = try c.value(.dailyReviewMinute, or: d.dailyReviewMinute)
        attendance = try c.value(.attendance, or: d.attendance)
    }
}

/// docs/SPEC.md "백업". Only the Mac app backs up.
public struct BackupSettings: Codable, Sendable, Equatable {
    public var enabled = true
    /// Local folder outside iCloud; `~` is expanded on the device that backs up.
    public var folder = "~/Backups/Folio/auto"
    /// Archives newer than this are all kept; older ones thin out to one per week.
    public var dailyDays = 30

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabled = try c.value(.enabled, or: d.enabled)
        folder = try c.value(.folder, or: d.folder)
        dailyDays = try c.value(.dailyDays, or: d.dailyDays)
    }
}

extension KeyedDecodingContainer {
    /// Settings files from older app versions lack newer keys; those fall back to the default.
    func value<T: Decodable>(_ key: Key, or fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
