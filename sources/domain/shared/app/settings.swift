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

extension KeyedDecodingContainer {
    // 예전 앱의 설정 파일에는 새 키가 없으므로, 없는 키는 기본값으로 읽는다.
    func value<T: Decodable>(_ key: Key, or fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
