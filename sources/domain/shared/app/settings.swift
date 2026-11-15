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
    public var idleMinutes: Int
    public var todayExamDays: Int
    public var urgency: UrgencySettings
    public var schedule: ScheduleDefaults
    public var gradesUnlockMinutes: Int
    public var school: SchoolSettings
    // 기본 종류 밖의 콜아웃 종류다. nil이면 기본 종류만 쓴다.
    public var callouts: [NoteCallout]?
    // 기본 종류 표가 앱과 함께 늘어날 수 있도록, 바꾸기 전까지는 nil로 둔다.
    public var assignmentKinds: [AssignmentKind]?

    public static let defaultNoteRules = SettingItem.noteRules.text

    public init(
        dayBoundaryMinutes: Int = SettingItem.dayBoundary.int, review: ReviewSettings = .init(),
        noteRules: String = Settings.defaultNoteRules, notifications: NotificationSettings = .init(), backup: BackupSettings = .init(),
        noteTemplates: [String: [String]] = [:], newNoteMath: MathSyntax = SettingItem.newNoteMath.choice(),
        sidebar: SidebarOrder = .init(), classMinutes: Int = SettingItem.classMinutes.int, mathSnippets: [MathSnippet]? = nil,
        asciiMathSnippets: [MathSnippet]? = nil, classStart: ClassStartSettings = .init(), panePresets: [PanePreset] = [],
        lms: LMSSettings = .init(), idleMinutes: Int = SettingItem.idleMinutes.int, todayExamDays: Int = SettingItem.todayExamDays.int,
        urgency: UrgencySettings = .init(), schedule: ScheduleDefaults = .init(),
        gradesUnlockMinutes: Int = SettingItem.gradesUnlockMinutes.int, school: SchoolSettings = .init(), callouts: [NoteCallout]? = nil,
        assignmentKinds: [AssignmentKind]? = nil
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
        self.idleMinutes = idleMinutes
        self.todayExamDays = todayExamDays
        self.urgency = urgency
        self.schedule = schedule
        self.gradesUnlockMinutes = gradesUnlockMinutes
        self.school = school
        self.callouts = callouts
        self.assignmentKinds = assignmentKinds
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
        idleMinutes = try c.value(.idleMinutes, or: d.idleMinutes)
        todayExamDays = try c.value(.todayExamDays, or: d.todayExamDays)
        urgency = try c.value(.urgency, or: d.urgency)
        schedule = try c.value(.schedule, or: d.schedule)
        gradesUnlockMinutes = try c.value(.gradesUnlockMinutes, or: d.gradesUnlockMinutes)
        school = try c.value(.school, or: d.school)
        callouts = try c.decodeIfPresent([NoteCallout].self, forKey: .callouts)
        assignmentKinds = try c.decodeIfPresent([AssignmentKind].self, forKey: .assignmentKinds)
    }

    public var presets: [PanePreset] { PanePreset.builtIn + panePresets }

    public var classStartPreset: PanePreset {
        classStart.preset.flatMap { id in presets.first { $0.id == id } } ?? .inClass
    }

    public var snippets: [MathSnippet] { mathSnippets ?? MathSnippet.defaults }
    public var asciiSnippets: [MathSnippet] { asciiMathSnippets ?? MathSnippet.asciiMathDefaults }
    public var assignmentKindTable: [AssignmentKind] { assignmentKinds ?? AssignmentKind.builtIn }

    public func noteSections(for kind: NoteKind) -> [String] {
        (noteTemplates[kind.rawValue] ?? NoteTemplate.defaultSections(for: kind)).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    public func studyDay(of date: Date, calendar: Calendar) -> LocalDate {
        LocalDate(calendar.date(byAdding: .minute, value: -dayBoundaryMinutes, to: date)!, in: calendar)
    }

    // 공부일이 시작하는 시각이다. 그날 자정에 하루 경계를 더한다.
    public func start(of day: LocalDate, calendar: Calendar) -> Date {
        // `LocalDate`는 만들 때 날짜를 검사하므로 그날의 자정은 언제나 있다.
        let midnight = day.date(in: calendar) ?? .distantPast
        return calendar.date(byAdding: .minute, value: dayBoundaryMinutes, to: midnight) ?? midnight
    }

    public func nextDayStart(after now: Date, calendar: Calendar) -> Date {
        start(of: studyDay(of: now, calendar: calendar).adding(days: 1), calendar: calendar)
    }

    // 설정 화면의 행이 항목의 키로 값을 읽고 쓴다(`SettingItem.current(in:)`, `writing(_:into:)`). 행마다 필드를 손으로 잇지 않으려고
    // JSON 모양을 거친다.
    public var json: JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self))) ?? .null
    }
}

extension KeyedDecodingContainer {
    // 예전 앱의 설정 파일에는 새 키가 없으므로, 없는 키는 기본값으로 읽는다.
    func value<T: Decodable>(_ key: Key, or fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
