import Foundation

public struct Settings: Codable, Sendable, Equatable {
    public var dayBoundaryMinutes: Int
    public var review: ReviewSettings
    public var noteRules: String
    public var notifications: NotificationSettings
    public var backup: BackupSettings
    public var noteTemplates: [String: [String]]
    public var newNoteMath: MathSyntax
    public var sidebar: SidebarOrder
    public var classMinutes: Int
    // 기본값이 앱과 함께 늘어날 수 있도록, 바꾸기 전까지는 nil로 둔다.
    public var mathSnippets: [MathSnippet]?
    public var asciiMathSnippets: [MathSnippet]?
    public var classStart: ClassStartSettings
    public var panePresets: [PanePreset]
    public var lms: LMSSettings

    public static let defaultNoteRules = """
        - 정의는 전제, 조건, 결론 순서로 쓴다.
        - 수학적 진술은 영어와 기호로, 설명은 한국어로 쓴다.
        - display 수식은 하나씩 나눠 쓴다.
        """

    public init(
        dayBoundaryMinutes: Int = 240, review: ReviewSettings = .init(), noteRules: String = Settings.defaultNoteRules,
        notifications: NotificationSettings = .init(), backup: BackupSettings = .init(), noteTemplates: [String: [String]] = [:],
        newNoteMath: MathSyntax = .asciimath, sidebar: SidebarOrder = .init(), classMinutes: Int = 75,
        mathSnippets: [MathSnippet]? = nil, asciiMathSnippets: [MathSnippet]? = nil, classStart: ClassStartSettings = .init(),
        panePresets: [PanePreset] = [], lms: LMSSettings = .init()
    ) {
        self.dayBoundaryMinutes = dayBoundaryMinutes
        self.review = review
        self.noteRules = noteRules
        self.notifications = notifications
        self.backup = backup
        self.noteTemplates = noteTemplates
        self.newNoteMath = newNoteMath
        self.sidebar = sidebar
        self.classMinutes = classMinutes
        self.mathSnippets = mathSnippets
        self.asciiMathSnippets = asciiMathSnippets
        self.classStart = classStart
        self.panePresets = panePresets
        self.lms = lms
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
        classMinutes = try c.value(.classMinutes, or: d.classMinutes)
        mathSnippets = try c.decodeIfPresent([MathSnippet].self, forKey: .mathSnippets)
        asciiMathSnippets = try c.decodeIfPresent([MathSnippet].self, forKey: .asciiMathSnippets)
        classStart = try c.value(.classStart, or: d.classStart)
        panePresets = try c.value(.panePresets, or: d.panePresets)
        lms = try c.value(.lms, or: d.lms)
    }

    public var presets: [PanePreset] { PanePreset.builtIn + panePresets }

    public var classStartPreset: PanePreset {
        classStart.preset.flatMap { id in presets.first { $0.id == id } } ?? .inClass
    }

    public var snippets: [MathSnippet] { mathSnippets ?? MathSnippet.defaults }
    public var asciiSnippets: [MathSnippet] { asciiMathSnippets ?? MathSnippet.asciiMathDefaults }

    public func noteSections(for kind: NoteKind) -> [String] {
        (noteTemplates[kind.rawValue] ?? NoteTemplate.defaultSections(for: kind)).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    public func studyDay(of date: Date, calendar: Calendar) -> LocalDate {
        LocalDate(calendar.date(byAdding: .minute, value: -dayBoundaryMinutes, to: date)!, in: calendar)
    }
}

public struct ReviewSettings: Codable, Sendable, Equatable {
    public var intervals: [Int]
    public var settleAfterPasses: Int
    public var dailyLimit: Int?
    public var examWindowDays: Int
    public var cardsPerReview: Int
    public var weights: PriorityWeights

    public init(
        intervals: [Int] = [1, 3, 7, 14, 30], settleAfterPasses: Int = 2, dailyLimit: Int? = nil,
        examWindowDays: Int = 7, cardsPerReview: Int = 5, weights: PriorityWeights = .init()
    ) {
        self.intervals = intervals
        self.settleAfterPasses = settleAfterPasses
        self.dailyLimit = dailyLimit
        self.examWindowDays = examWindowDays
        self.cardsPerReview = cardsPerReview
        self.weights = weights
    }

    public func interval(atStep step: Int) -> Int { intervals[min(max(step, 0), intervals.count - 1)] }

    public func reviewDays(after day: LocalDate) -> [LocalDate] {
        var next = day
        return intervals.map {
            next = next.adding(days: $0); return next
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReviewSettings()
        // 모든 단계를 인덱스로 쓰고 나눗셈에도 쓰므로, 손으로 고친 목록이 비었거나 양수가 아니면 기본값으로 돌아간다.
        let decoded = try c.decodeIfPresent([Int].self, forKey: .intervals)?.filter { $0 > 0 } ?? []
        intervals = decoded.isEmpty ? d.intervals : decoded
        settleAfterPasses = try c.decodeIfPresent(Int.self, forKey: .settleAfterPasses) ?? d.settleAfterPasses
        dailyLimit = try c.decodeIfPresent(Int.self, forKey: .dailyLimit)
        examWindowDays = try c.decodeIfPresent(Int.self, forKey: .examWindowDays) ?? d.examWindowDays
        cardsPerReview = try c.decodeIfPresent(Int.self, forKey: .cardsPerReview) ?? d.cardsPerReview
        weights = try c.decodeIfPresent(PriorityWeights.self, forKey: .weights) ?? d.weights
    }
}

public struct PriorityWeights: Codable, Sendable, Equatable {
    public var overdue: Double
    public var exam: Double
    public var quizMiss: Double
    public var openWrong: Double

    public init(overdue: Double = 1, exam: Double = 3, quizMiss: Double = 1, openWrong: Double = 0.2) {
        self.overdue = overdue
        self.exam = exam
        self.quizMiss = quizMiss
        self.openWrong = openWrong
    }
}

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

public struct BackupSettings: Codable, Sendable, Equatable {
    public var enabled = true
    public var folder = "~/Backups/Folio/auto"
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
    // 예전 앱의 설정 파일에는 새 키가 없으므로, 없는 키는 기본값으로 읽는다.
    func value<T: Decodable>(_ key: Key, or fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
