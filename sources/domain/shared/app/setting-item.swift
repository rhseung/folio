import Foundation

// `settings.json`의 항목 하나다. 키는 settings.json의 이름을 점으로 이은 경로이고, 설정 화면의 범위와 `settings set`의
// 검사가 같은 선언을 읽는다.
public struct SettingItem: Sendable, Equatable {
    public enum Shape: Sendable, Equatable {
        case toggle
        case number(ClosedRange<Int>)
        case positive
        // 정수 목록이다. 값마다 범위 안이어야 하고 목록은 비지 않는다.
        case numbers(ClosedRange<Int>)
        // 자정부터 센 분이다. 시는 이 범위 안에서 고른다.
        case time(hours: ClosedRange<Int>)
        case choice([String])
        case text
        // 목록, 사전, 배치처럼 모양을 디코딩으로만 확인하는 값이다. 그 아래 키도 이 항목에 속한다.
        case custom
    }

    public let key: String
    public let shape: Shape
    // `null`로 지울 수 있다. 지우면 앱이 기본값을 쓴다.
    public let optional: Bool
    // 설정 화면에서 이 항목을 보이는 탭이다. 다른 화면이 바꾸는 값(사이드바 순서)이면 nil이다.
    public let page: AppLink.SettingsPage?

    init(_ key: String, _ shape: Shape, optional: Bool = false, page: AppLink.SettingsPage?) {
        self.key = key
        self.shape = shape
        self.optional = optional
        self.page = page
    }

    public var range: ClosedRange<Int> {
        switch shape {
        case .number(let r), .numbers(let r): r
        case .time(let hours): hours.lowerBound * 60...hours.upperBound * 60 + 59
        case .positive: 1...Int.max
        case .toggle, .choice, .text, .custom: Int.min...Int.max
        }
    }

    public var hours: ClosedRange<Int> {
        if case .time(let hours) = shape { hours } else { 0...23 }
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
            var node: JSONValue? = root
            for key in item.key.split(separator: ".") { node = node?[String(key)] }
            if let node, let problem = item.problem(node) { found.append(problem) }
        }
        return found
    }
}

extension SettingItem {
    public static let dayBoundary = SettingItem("dayBoundaryMinutes", .time(hours: 0...8), page: .general)
    public static let panePresets = SettingItem("panePresets", .custom, page: .general)

    public static let reviewIntervals = SettingItem("review.intervals", .numbers(1...365), page: .review)
    public static let reviewDailyLimit = SettingItem("review.dailyLimit", .number(1...50), optional: true, page: .review)
    public static let reviewExamWindow = SettingItem("review.examWindowDays", .number(0...30), page: .review)
    public static let reviewCardsPerReview = SettingItem("review.cardsPerReview", .number(1...20), page: .review)
    public static let reviewSettleAfter = SettingItem("review.settleAfterPasses", .number(1...5), page: .review)
    public static let reviewWeights = SettingItem("review.weights", .custom, page: nil)

    public static let assignmentDue = SettingItem("notifications.assignmentDue", .toggle, page: .notifications)
    public static let assignmentLeadHours = SettingItem("notifications.assignmentLeadHours", .numbers(1...336), page: .notifications)
    public static let examDayBefore = SettingItem("notifications.examDayBefore", .toggle, page: .notifications)
    public static let examDayBeforeMinute = SettingItem("notifications.examDayBeforeMinute", .time(hours: 0...23), page: .notifications)
    public static let examMorning = SettingItem("notifications.examMorning", .toggle, page: .notifications)
    public static let examMorningMinute = SettingItem("notifications.examMorningMinute", .time(hours: 0...23), page: .notifications)
    public static let dailyReview = SettingItem("notifications.dailyReview", .toggle, page: .notifications)
    public static let dailyReviewMinute = SettingItem("notifications.dailyReviewMinute", .time(hours: 0...23), page: .notifications)
    public static let attendance = SettingItem("notifications.attendance", .toggle, page: .notifications)

    public static let backupEnabled = SettingItem("backup.enabled", .toggle, page: .backup)
    public static let backupFolder = SettingItem("backup.folder", .text, page: .backup)
    public static let backupDailyDays = SettingItem("backup.dailyDays", .positive, page: .backup)

    public static let noteRules = SettingItem("noteRules", .text, page: .claude)
    public static let noteTemplates = SettingItem("noteTemplates", .custom, page: .notes)
    public static let newNoteMath = SettingItem("newNoteMath", .choice(MathSyntax.allCases.map(\.rawValue)), page: .notes)
    public static let mathSnippets = SettingItem("mathSnippets", .custom, optional: true, page: .notes)
    public static let asciiMathSnippets = SettingItem("asciiMathSnippets", .custom, optional: true, page: .notes)

    public static let classMinutes = SettingItem("classMinutes", .number(10...300), page: .classes)
    public static let classRecording = SettingItem(
        "classStart.recording", .choice(ClassStartSettings.Recording.allCases.map(\.rawValue)), page: .classes)
    public static let classRecordingOffset = SettingItem("classStart.recordingOffsetMinutes", .number(-60...60), page: .classes)
    public static let classStopsRecording = SettingItem("classStart.stopsRecording", .toggle, page: .classes)
    public static let classStopAfter = SettingItem("classStart.stopAfterMinutes", .number(-60...60), page: .classes)
    public static let classRoughNote = SettingItem(
        "classStart.roughNote", .choice(ClassStartSettings.RoughNote.allCases.map(\.rawValue)), page: .classes)
    public static let classRoughNotePlace = SettingItem(
        "classStart.roughNotePlace", .choice(ClassStartSettings.Place.allCases.map(\.rawValue)), page: .classes)
    public static let classLecture = SettingItem(
        "classStart.lecture", .choice(ClassStartSettings.Lecture.allCases.map(\.rawValue)), page: .classes)
    public static let classLecturePlace = SettingItem(
        "classStart.lecturePlace", .choice(ClassStartSettings.Place.allCases.map(\.rawValue)), page: .classes)
    public static let classOpenIn = SettingItem(
        "classStart.openIn", .choice(ClassStartSettings.OpenIn.allCases.map(\.rawValue)), page: .classes)
    public static let classAllLectures = SettingItem("classStart.allLectures", .toggle, page: .classes)
    public static let classResumesLecture = SettingItem("classStart.resumesLecture", .toggle, page: .classes)
    public static let classScreen = SettingItem(
        "classStart.screen", .choice(ClassStartSettings.Screen.allCases.map(\.rawValue)), page: .classes)
    public static let classPreset = SettingItem("classStart.preset", .text, optional: true, page: .classes)
    public static let classCourseOff = SettingItem("classStart.courseOff", .custom, page: .classes)

    public static let sidebar = SettingItem("sidebar", .custom, page: nil)
    public static let lms = SettingItem("lms", .custom, page: .lms)

    public static let all: [SettingItem] = [
        dayBoundary, panePresets,
        reviewIntervals, reviewDailyLimit, reviewExamWindow, reviewCardsPerReview, reviewSettleAfter, reviewWeights,
        assignmentDue, assignmentLeadHours, examDayBefore, examDayBeforeMinute, examMorning, examMorningMinute, dailyReview,
        dailyReviewMinute, attendance,
        backupEnabled, backupFolder, backupDailyDays,
        noteRules, noteTemplates, newNoteMath, mathSnippets, asciiMathSnippets,
        classMinutes, classRecording, classRecordingOffset, classStopsRecording, classStopAfter, classRoughNote, classRoughNotePlace,
        classLecture, classLecturePlace, classOpenIn, classAllLectures, classResumesLecture, classScreen, classPreset, classCourseOff,
        sidebar, lms,
    ]
}
