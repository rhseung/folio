import Foundation

// `settings.json`의 항목 하나다. 키는 settings.json의 이름을 점으로 이은 경로이고, 기본값의 단일 출처다. `Settings`의 기본값,
// 설정 화면의 범위, `settings set`의 검사, `settings show`와 MCP 입력 형식이 같은 선언을 읽는다.
public struct SettingItem: Sendable {
    public enum Shape: Sendable, Equatable {
        case toggle
        case number(ClosedRange<Int>)
        case positive
        // 정수 목록이다. 값마다 범위 안이어야 하고 목록은 비지 않는다.
        case numbers(ClosedRange<Int>)
        // 자정부터 센 분이다. 화면은 이 범위가 걸친 시 안에서 고른다.
        case time(ClosedRange<Int>)
        case choice([String])
        case text
        // 목록, 사전, 배치처럼 모양을 디코딩으로만 확인하는 값이다. 그 아래 키도 이 항목에 속한다.
        case custom
    }

    public let key: String
    public let shape: Shape
    // 파일에 없을 때 쓰는 값이다. 지울 수 있는 항목이 비어 있으면 `.null`이다.
    public let fallback: JSONValue
    // `null`로 지울 수 있다. 지우면 앱이 기본값을 쓴다.
    public let optional: Bool
    // 설정 화면에서 이 항목을 보이는 탭이다. 다른 화면이 바꾸는 값(사이드바 순서)이면 nil이다.
    public let page: AppLink.SettingsPage?
    public let name: LocalizedStringResource

    init(
        _ key: String, _ shape: Shape, _ fallback: JSONValue, optional: Bool = false, page: AppLink.SettingsPage?,
        name: LocalizedStringResource
    ) {
        self.key = key
        self.shape = shape
        self.fallback = fallback
        self.optional = optional
        self.page = page
        self.name = name
    }

    public var range: ClosedRange<Int> {
        switch shape {
        case .number(let r), .numbers(let r): r
        case .time(let minutes): minutes
        case .positive: 1...Int.max
        case .toggle, .choice, .text, .custom: Int.min...Int.max
        }
    }

    public var hours: ClosedRange<Int> {
        if case .time(let minutes) = shape { minutes.lowerBound / 60...minutes.upperBound / 60 } else { 0...23 }
    }

    public func problem(_ value: JSONValue) -> String? {
        if value == .null { return optional ? nil : String(localized: .settingEmpty(key)) }
        switch shape {
        case .toggle:
            if case .bool = value { return nil }
            return String(localized: .settingNotBool(key))
        case .number, .time, .positive:
            return problem(whole: value)
        case .numbers:
            guard case .array(let values) = value else { return String(localized: .settingNotList(key)) }
            if values.isEmpty { return String(localized: .settingEmpty(key)) }
            return values.lazy.compactMap { problem(whole: $0) }.first
        case .choice(let options):
            if case .string(let s) = value, options.contains(s) { return nil }
            return String(localized: .settingNotChoice(key, options.joined(separator: ", ")))
        case .text:
            if case .string = value { return nil }
            return String(localized: .settingNotText(key))
        case .custom:
            return nil
        }
    }

    private func problem(whole value: JSONValue) -> String? {
        guard case .number(let d) = value, d.rounded() == d, let n = Int(exactly: d) else {
            return String(localized: .settingNotWhole(key))
        }
        guard !range.contains(n) else { return nil }
        if shape == .positive { return String(localized: .settingNotPositive(key)) }
        return String(localized: .settingOutOfRange(key, range.lowerBound, range.upperBound))
    }

    // 필드가 이 항목이거나 이 항목을 담는 객체이거나 모양을 따로 보지 않는 항목의 안쪽이다.
    public func touches(_ field: String) -> Bool {
        key == field || key.hasPrefix(field + ".") || (shape == .custom && field.hasPrefix(key + "."))
    }

    public static func unknown(_ field: String) -> String? {
        all.contains { $0.touches(field) } ? nil : String(localized: .settingUnknown(field))
    }

    // `field`가 nil이면 모든 항목을 본다. 파일에 없는 키는 디코딩이 기본값으로 채우므로 보지 않는다.
    public static func problems(in root: JSONValue, under field: String? = nil) -> [String] {
        var found: [String] = []
        for item in all where field.map(item.touches) ?? true {
            if let node = item.value(in: root), let problem = item.problem(node) { found.append(problem) }
        }
        return found
    }

    public func value(in root: JSONValue) -> JSONValue? {
        key.split(separator: ".").reduce(Optional(root)) { node, key in node?[String(key)] }
    }

    public static func item(_ key: String) -> SettingItem? { all.first { $0.key == key } }
}

extension SettingItem {
    // 선언한 기본값을 `Settings`의 필드가 읽는다. 기본값의 모양이 선언과 다르면 앱이 시작하자마자 멈추고, 테스트도 모든 항목을 읽어
    // 본다.
    public var int: Int {
        guard case .number(let d) = fallback, let n = Int(exactly: d) else { preconditionFailure(key) }
        return n
    }

    public var ints: [Int] {
        guard case .array(let values) = fallback else { preconditionFailure(key) }
        return values.map { v in
            guard case .number(let d) = v, let n = Int(exactly: d) else { preconditionFailure(key) }
            return n
        }
    }

    public var bool: Bool {
        guard case .bool(let b) = fallback else { preconditionFailure(key) }
        return b
    }

    public var text: String {
        guard case .string(let s) = fallback else { preconditionFailure(key) }
        return s
    }

    public func choice<T: RawRepresentable>(_: T.Type = T.self) -> T where T.RawValue == String {
        guard case .string(let s) = fallback, let value = T(rawValue: s) else { preconditionFailure(key) }
        return value
    }

    static func encoded(_ value: some Encodable) -> JSONValue {
        // 모양을 디코딩으로만 보는 값은 그 타입의 빈 값이 기본값이다.
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }
}

extension SettingItem {
    public static let dayBoundary = SettingItem(
        "dayBoundaryMinutes", .time(0...8 * 60), 240, page: .general, name: .settingItemDayBoundaryMinutes)
    public static let idleMinutes = SettingItem("idleMinutes", .number(1...60), 5, page: .general, name: .settingItemIdleMinutes)
    public static let panePresets = SettingItem("panePresets", .custom, [], page: .general, name: .settingItemPanePresets)

    public static let todayExamDays = SettingItem("todayExamDays", .number(1...365), 30, page: .general, name: .settingItemTodayExamDays)
    public static let assignmentUrgentDays = SettingItem(
        "urgency.assignmentUrgentDays", .number(0...30), 1, page: .general, name: .settingItemUrgencyAssignmentUrgentDays)
    public static let assignmentSoonDays = SettingItem(
        "urgency.assignmentSoonDays", .number(1...60), 7, page: .general, name: .settingItemUrgencyAssignmentSoonDays)
    public static let examUrgentDays = SettingItem(
        "urgency.examUrgentDays", .number(0...30), 3, page: .general, name: .settingItemUrgencyExamUrgentDays)
    public static let examSoonDays = SettingItem(
        "urgency.examSoonDays", .number(1...60), 7, page: .general, name: .settingItemUrgencyExamSoonDays)
    public static let examNearDays = SettingItem(
        "urgency.examNearDays", .number(1...90), 14, page: .general, name: .settingItemUrgencyExamNearDays)

    public static let dueMinute = SettingItem(
        "schedule.dueMinute", .time(0...24 * 60 - 1), .number(23 * 60 + 59), page: .general, name: .settingItemScheduleDueMinute)
    public static let examStartMinute = SettingItem(
        "schedule.examStartMinute", .time(0...24 * 60 - 1), .number(9 * 60), page: .general, name: .settingItemScheduleExamStartMinute)
    public static let examMinutes = SettingItem(
        "schedule.examMinutes", .number(10...600), 120, page: .general, name: .settingItemScheduleExamMinutes)
    public static let sessionStartMinute = SettingItem(
        "schedule.sessionStartMinute", .time(0...24 * 60 - 1), .number(18 * 60), page: .classes,
        name: .settingItemScheduleSessionStartMinute)
    public static let classStartMinute = SettingItem(
        "schedule.classStartMinute", .time(0...24 * 60 - 1), .number(10 * 60 + 30), page: .classes,
        name: .settingItemScheduleClassStartMinute)

    public static let gradesUnlockMinutes = SettingItem(
        "gradesUnlockMinutes", .number(1...60), 5, page: .record, name: .settingItemGradesUnlockMinutes)
    public static let staffMailDomain = SettingItem(
        "school.staffMailDomain", .text, "gist.ac.kr", page: .record, name: .settingItemSchoolStaffMailDomain)
    public static let studentMailDomain = SettingItem(
        "school.studentMailDomain", .text, "gm.gist.ac.kr", page: .record, name: .settingItemSchoolStudentMailDomain)

    public static let reviewIntervals = SettingItem(
        "review.intervals", .numbers(1...365), [1, 3, 7, 14, 30], page: .review, name: .settingItemReviewIntervals)
    public static let reviewDailyLimit = SettingItem(
        "review.dailyLimit", .number(1...50), .null, optional: true, page: .review, name: .settingItemReviewDailyLimit)
    public static let reviewExamWindow = SettingItem(
        "review.examWindowDays", .number(0...30), 7, page: .review, name: .settingItemReviewExamWindowDays)
    public static let reviewCardsPerReview = SettingItem(
        "review.cardsPerReview", .number(1...20), 5, page: .review, name: .settingItemReviewCardsPerReview)
    public static let reviewSettleAfter = SettingItem(
        "review.settleAfterPasses", .number(1...5), 2, page: .review, name: .settingItemReviewSettleAfterPasses)
    public static let quizRecheckDays = SettingItem(
        "review.quizRecheckDays", .number(1...60), 7, page: .review, name: .settingItemReviewQuizRecheckDays)
    public static let reviewWeights = SettingItem(
        "review.weights", .custom, encoded(PriorityWeights()), page: nil, name: .settingItemReviewWeights)
    public static let callouts = SettingItem("callouts", .custom, .null, optional: true, page: .notes, name: .settingItemCallouts)

    // 알림 종류마다 `notifications.<종류>.<칸>`이다. `NotificationSettings.Kind.item`이 이 키로 종류의 칸과 기본값을 찾는다.
    public static let assignmentDue = SettingItem(
        "notifications.assignmentDue.on", .toggle, true, page: .notifications, name: .settingItemNotificationsAssignmentDueOn)
    public static let assignmentLeadHours = SettingItem(
        "notifications.assignmentDue.leadHours", .numbers(1...336), [24, 3], page: .notifications,
        name: .settingItemNotificationsAssignmentDueLeadHours)
    public static let examDayBefore = SettingItem(
        "notifications.examDayBefore.on", .toggle, true, page: .notifications, name: .settingItemNotificationsExamDayBeforeOn)
    public static let examDayBeforeMinute = SettingItem(
        "notifications.examDayBefore.minute", .time(0...24 * 60 - 1), .number(21 * 60), page: .notifications,
        name: .settingItemNotificationsExamDayBeforeMinute)
    public static let examMorning = SettingItem(
        "notifications.examMorning.on", .toggle, true, page: .notifications, name: .settingItemNotificationsExamMorningOn)
    public static let examMorningMinute = SettingItem(
        "notifications.examMorning.minute", .time(0...24 * 60 - 1), .number(8 * 60), page: .notifications,
        name: .settingItemNotificationsExamMorningMinute)
    public static let dailyReview = SettingItem(
        "notifications.dailyReview.on", .toggle, true, page: .notifications, name: .settingItemNotificationsDailyReviewOn)
    public static let dailyReviewMinute = SettingItem(
        "notifications.dailyReview.minute", .time(0...24 * 60 - 1), .number(9 * 60), page: .notifications,
        name: .settingItemNotificationsDailyReviewMinute)
    public static let attendance = SettingItem(
        "notifications.attendance.on", .toggle, true, page: .notifications, name: .settingItemNotificationsAttendanceOn)

    public static let backupEnabled = SettingItem("backup.enabled", .toggle, true, page: .backup, name: .settingItemBackupEnabled)
    public static let backupFolder = SettingItem(
        "backup.folder", .text, "~/Backups/Folio/auto", page: .backup, name: .settingItemBackupFolder)
    public static let backupDailyDays = SettingItem("backup.dailyDays", .positive, 30, page: .backup, name: .settingItemBackupDailyDays)

    public static let noteRules = SettingItem(
        "noteRules", .text,
        .string(
            """
            - 정의는 전제, 조건, 결론 순서로 쓴다.
            - 수학적 진술은 영어와 기호로, 설명은 한국어로 쓴다.
            - display 수식은 하나씩 나눠 쓴다.
            """), page: .claude, name: .settingItemNoteRules)
    public static let noteTemplates = SettingItem("noteTemplates", .custom, [:], page: .notes, name: .settingItemNoteTemplates)
    public static let newNoteMath = SettingItem(
        "newNoteMath", .choice(MathSyntax.allCases.map(\.rawValue)), .string(MathSyntax.asciimath.rawValue), page: .notes,
        name: .settingItemNewNoteMath)
    public static let mathSnippets = SettingItem(
        "mathSnippets", .custom, .null, optional: true, page: .notes, name: .settingItemMathSnippets)
    public static let asciiMathSnippets = SettingItem(
        "asciiMathSnippets", .custom, .null, optional: true, page: .notes, name: .settingItemAsciiMathSnippets)

    public static let classMinutes = SettingItem("classMinutes", .number(10...300), 75, page: .classes, name: .settingItemClassMinutes)
    public static let classRecording = choice("classStart.recording", ClassStartSettings.Recording.off, .settingItemClassStartRecording)
    public static let classRecordingOffset = SettingItem(
        "classStart.recordingOffsetMinutes", .number(-60...60), 0, page: .classes, name: .settingItemClassStartRecordingOffsetMinutes)
    public static let classStopsRecording = SettingItem(
        "classStart.stopsRecording", .toggle, false, page: .classes, name: .settingItemClassStartStopsRecording)
    public static let classStopAfter = SettingItem(
        "classStart.stopAfterMinutes", .number(-60...60), 0, page: .classes, name: .settingItemClassStartStopAfterMinutes)
    public static let classRoughNote = choice("classStart.roughNote", ClassStartSettings.RoughNote.off, .settingItemClassStartRoughNote)
    public static let classRoughNotePlace = choice(
        "classStart.roughNotePlace", ClassStartSettings.Place.here, .settingItemClassStartRoughNotePlace)
    public static let classLecture = choice("classStart.lecture", ClassStartSettings.Lecture.off, .settingItemClassStartLecture)
    public static let classLecturePlace = choice(
        "classStart.lecturePlace", ClassStartSettings.Place.beside, .settingItemClassStartLecturePlace)
    public static let classOpenIn = choice("classStart.openIn", ClassStartSettings.OpenIn.splitTab, .settingItemClassStartOpenIn)
    public static let classAllLectures = SettingItem(
        "classStart.allLectures", .toggle, false, page: .classes, name: .settingItemClassStartAllLectures)
    public static let classResumesLecture = SettingItem(
        "classStart.resumesLecture", .toggle, true, page: .classes, name: .settingItemClassStartResumesLecture)
    public static let classScreen = choice("classStart.screen", ClassStartSettings.Screen.notify, .settingItemClassStartScreen)
    public static let classPreset = SettingItem(
        "classStart.preset", .text, .null, optional: true, page: .classes, name: .settingItemClassStartPreset)
    public static let classCourseOff = SettingItem(
        "classStart.courseOff", .custom, [:], page: .classes, name: .settingItemClassStartCourseOff)

    public static let sidebar = SettingItem("sidebar", .custom, encoded(SidebarOrder()), page: nil, name: .settingItemSidebar)
    public static let lmsKnown = SettingItem("lms.known", .custom, [], page: nil, name: .settingItemLmsKnown)
    public static let lmsHandled = SettingItem("lms.handled", .custom, [], page: nil, name: .settingItemLmsHandled)
    public static let lmsSyncMinutes = SettingItem("lms.syncMinutes", .number(5...1440), 30, page: .lms, name: .settingItemLmsSyncMinutes)
    public static let assignmentKinds = SettingItem(
        "assignmentKinds", .custom, .null, optional: true, page: nil, name: .settingItemAssignmentKinds)

    private static func choice<T: RawRepresentable & CaseIterable>(_ key: String, _ fallback: T, _ name: LocalizedStringResource)
        -> SettingItem where T.RawValue == String
    {
        SettingItem(key, .choice(T.allCases.map(\.rawValue)), .string(fallback.rawValue), page: .classes, name: name)
    }

    public static let all: [SettingItem] = [
        dayBoundary, idleMinutes, panePresets,
        todayExamDays, assignmentUrgentDays, assignmentSoonDays, examUrgentDays, examSoonDays, examNearDays,
        dueMinute, examStartMinute, examMinutes, sessionStartMinute, classStartMinute,
        gradesUnlockMinutes, staffMailDomain, studentMailDomain,
        reviewIntervals, reviewDailyLimit, reviewExamWindow, reviewCardsPerReview, reviewSettleAfter, quizRecheckDays, reviewWeights,
        assignmentDue, assignmentLeadHours, examDayBefore, examDayBeforeMinute, examMorning, examMorningMinute, dailyReview,
        dailyReviewMinute, attendance,
        backupEnabled, backupFolder, backupDailyDays,
        noteRules, noteTemplates, newNoteMath, mathSnippets, asciiMathSnippets, callouts,
        classMinutes, classRecording, classRecordingOffset, classStopsRecording, classStopAfter, classRoughNote, classRoughNotePlace,
        classLecture, classLecturePlace, classOpenIn, classAllLectures, classResumesLecture, classScreen, classPreset, classCourseOff,
        sidebar, lmsKnown, lmsHandled, lmsSyncMinutes, assignmentKinds,
    ]
}
