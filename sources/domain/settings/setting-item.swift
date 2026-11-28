import FolioCore
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
        // 값은 자정부터 센 분이고, 범위는 시로 적는다. 화면이 시를 고른 뒤 그 시의 분을 고르므로, 끝 시의 59분까지 받아야
        // 화면에서 고를 수 있는 값을 저장 검사가 거절하지 않는다.
        case time(hours: ClosedRange<Int>)
        case choice([String])
        case text
        // 여러 줄 글이다. 값의 검사는 `text`와 같다.
        case prose
        // 목록, 사전, 배치처럼 모양을 디코딩으로만 확인하는 값이다. 그 아래 키도 이 항목에 속한다.
        case custom
    }

    // 설정 화면에서 이 항목이 놓이는 곳이다.
    public enum Place: Sendable, Equatable {
        // 묶음 안에서 선언으로 그린 행이다.
        case row(SettingGroup)
        // 묶음의 "세부" 안에 선언으로 그린 행이다.
        case more(SettingGroup)
        // 그 탭이 따로 그린다. 목록을 고치거나 그림, 폴더 고르기처럼 행 하나로 그릴 수 없는 항목이다.
        case own(AppLink.SettingsPage)
        // 설정 화면 밖에서 바뀐다(사이드바 순서, LMS 기록).
        case outside
    }

    public struct Option: Sendable {
        public let value: String
        public let name: LocalizedStringResource
    }

    public let key: String
    public let shape: Shape
    // 파일에 없을 때 쓰는 값이다. 지울 수 있는 항목이 비어 있으면 `.null`이다.
    public let fallback: JSONValue
    // `null`로 지울 수 있다. 지우면 앱이 기본값을 쓴다.
    public let optional: Bool
    public let place: Place
    public let name: LocalizedStringResource
    public let unit: SettingUnit?
    // 숫자를 끌어서 바꿀 때 한 눈금이다.
    public let step: Int
    // 이 행을 켜고 끄는 토글 항목의 키다. 그 토글은 따로 행을 갖지 않고 이 행의 스위치가 된다.
    public let switchedBy: String?
    // 지울 수 있는 숫자 항목을 다시 켤 때 넣는 값이다.
    public let starting: Int?
    // 고르기 항목의 선택지 이름이다. 선언으로 그리는 고르기 행만 둔다.
    public let options: [Option]

    init(
        _ key: String, _ shape: Shape, _ fallback: JSONValue, optional: Bool = false, place: Place, name: LocalizedStringResource,
        unit: SettingUnit? = nil, step: Int = 1, switchedBy: SettingItem? = nil, starting: Int? = nil, options: [Option] = []
    ) {
        self.key = key
        self.shape = shape
        self.fallback = fallback
        self.optional = optional
        self.place = place
        self.name = name
        self.unit = unit
        self.step = step
        self.switchedBy = switchedBy?.key
        self.starting = starting
        self.options = options
    }

    // `settings show`가 항목을 탭마다 묶는다. 설정 화면 밖에서 바뀌는 항목이면 nil이다.
    public var page: AppLink.SettingsPage? {
        switch place {
        case .row(let group), .more(let group): group.page
        case .own(let page): page
        case .outside: nil
        }
    }

    public var group: SettingGroup? {
        switch place {
        case .row(let group), .more(let group): group
        case .own, .outside: nil
        }
    }

    public var range: ClosedRange<Int> {
        switch shape {
        case .number(let r), .numbers(let r): r
        case .time(let hours): hours.lowerBound * 60...hours.upperBound * 60 + 59
        case .positive: 1...Int.max
        case .toggle, .choice, .text, .prose, .custom: Int.min...Int.max
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
        case .text, .prose:
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

    // 파일에 없거나 비어 있으면 기본값이다. 지울 수 있는 항목만 비어 있는 값(`null`)을 그대로 준다.
    public func current(in root: JSONValue) -> JSONValue {
        let value = value(in: root) ?? .null
        return value == .null && !optional ? fallback : value
    }

    // 모양이 맞지 않으면 nil이다. 행은 선언의 범위 안에서만 값을 고르므로 검사는 디코딩이 한다.
    public func writing(_ value: JSONValue, into settings: Settings) -> Settings? {
        let root = Self.replacing(settings.json, at: key.split(separator: ".")[...], with: value)
        guard let data = try? JSONEncoder().encode(root) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: data)
    }

    private static func replacing(_ node: JSONValue, at keys: ArraySlice<Substring>, with value: JSONValue) -> JSONValue {
        guard let key = keys.first.map(String.init) else { return value }
        var object: [String: JSONValue] = if case .object(let o) = node { o } else { [:] }
        object[key] = replacing(object[key] ?? .null, at: keys.dropFirst(), with: value)
        return .object(object)
    }
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
        "dayBoundaryMinutes", .time(hours: 0...8), 240, place: .row(.day), name: .settingItemDayBoundaryMinutes)
    public static let idleMinutes = SettingItem(
        "idleMinutes", .number(1...60), 5, place: .row(.day), name: .settingItemIdleMinutes, unit: .minutes)
    public static let panePresets = SettingItem("panePresets", .custom, [], place: .own(.general), name: .settingItemPanePresets)

    public static let todayExamDays = SettingItem(
        "todayExamDays", .number(1...365), 30, place: .row(.deadlines), name: .settingItemTodayExamDays, unit: .days)
    public static let assignmentUrgentDays = SettingItem(
        "urgency.assignmentUrgentDays", .number(0...30), 1, place: .more(.deadlines), name: .settingItemUrgencyAssignmentUrgentDays,
        unit: .days)
    public static let assignmentSoonDays = SettingItem(
        "urgency.assignmentSoonDays", .number(1...60), 7, place: .more(.deadlines), name: .settingItemUrgencyAssignmentSoonDays,
        unit: .days)
    public static let examUrgentDays = SettingItem(
        "urgency.examUrgentDays", .number(0...30), 3, place: .more(.deadlines), name: .settingItemUrgencyExamUrgentDays, unit: .days)
    public static let examSoonDays = SettingItem(
        "urgency.examSoonDays", .number(1...60), 7, place: .more(.deadlines), name: .settingItemUrgencyExamSoonDays, unit: .days)
    public static let examNearDays = SettingItem(
        "urgency.examNearDays", .number(1...90), 14, place: .more(.deadlines), name: .settingItemUrgencyExamNearDays, unit: .days)

    public static let dueMinute = SettingItem(
        "schedule.dueMinute", .time(hours: 0...23), .number(23 * 60 + 59), place: .row(.deadlines),
        name: .settingItemScheduleDueMinute)
    public static let examStartMinute = SettingItem(
        "schedule.examStartMinute", .time(hours: 0...23), .number(9 * 60), place: .more(.deadlines),
        name: .settingItemScheduleExamStartMinute)
    public static let examMinutes = SettingItem(
        "schedule.examMinutes", .number(10...600), 120, place: .more(.deadlines), name: .settingItemScheduleExamMinutes, unit: .minutes,
        step: 10)

    public static let classMinutes = SettingItem(
        "classMinutes", .number(10...300), 75, place: .row(.classTime), name: .settingItemClassMinutes, unit: .minutes, step: 5)
    public static let classStartMinute = SettingItem(
        "schedule.classStartMinute", .time(hours: 0...23), .number(10 * 60 + 30), place: .row(.classTime),
        name: .settingItemScheduleClassStartMinute)
    public static let sessionStartMinute = SettingItem(
        "schedule.sessionStartMinute", .time(hours: 0...23), .number(18 * 60), place: .row(.classTime),
        name: .settingItemScheduleSessionStartMinute)

    public static let gradesUnlockMinutes = SettingItem(
        "gradesUnlockMinutes", .number(1...60), 5, place: .row(.school), name: .settingItemGradesUnlockMinutes, unit: .minutes)
    public static let staffMailDomain = SettingItem(
        "school.staffMailDomain", .text, "gist.ac.kr", place: .row(.school), name: .settingItemSchoolStaffMailDomain)
    public static let studentMailDomain = SettingItem(
        "school.studentMailDomain", .text, "gm.gist.ac.kr", place: .row(.school), name: .settingItemSchoolStudentMailDomain)

    public static let studyReadyPercent = SettingItem(
        "study.readyPercent", .number(50...100), 80, place: .row(.study), name: .settingItemStudyReadyPercent, unit: .percent, step: 5)
    public static let studyMinProblems = SettingItem(
        "study.minProblems", .number(1...20), 3, place: .row(.study), name: .settingItemStudyMinProblems, unit: .problems)
    public static let studyMockMinutes = SettingItem(
        "study.mockMinutes", .number(10...300), 90, place: .row(.study), name: .settingItemStudyMockMinutes, unit: .minutes, step: 10)
    public static let studyPlanShownDays = SettingItem(
        "study.planShownDays", .number(1...14), 3, place: .row(.study), name: .settingItemStudyPlanShownDays, unit: .days)
    public static let studyAutoExtract = SettingItem(
        "study.autoExtract", .toggle, true, place: .row(.study), name: .settingItemStudyAutoExtract)
    // 이름은 사람마다 달라서 기본값이 비어 있다. 저장소가 공개라 픽스처에도 넣지 않는다.
    public static let studyCoverName = SettingItem(
        "study.coverName", .text, "", place: .row(.study), name: .settingItemStudyCoverName)
    public static let callouts = SettingItem("callouts", .custom, .null, optional: true, place: .own(.notes), name: .settingItemCallouts)

    // 알림 종류마다 `notifications.<종류>.<칸>`이다. `NotificationSettings.Kind.item`이 이 키로 종류의 칸과 기본값을 찾는다.
    public static let assignmentDue = SettingItem(
        "notifications.assignmentDue.on", .toggle, true, place: .row(.assignmentAlerts), name: .settingItemNotificationsAssignmentDueOn)
    public static let assignmentLeadHours = SettingItem(
        "notifications.assignmentDue.leadHours", .numbers(1...336), [24, 3], place: .row(.assignmentAlerts),
        name: .settingItemNotificationsAssignmentDueLeadHours, unit: .hoursBefore, switchedBy: assignmentDue)
    public static let assignmentOverdue = SettingItem(
        "notifications.assignmentOverdue.on", .toggle, true, place: .row(.assignmentAlerts),
        name: .settingItemNotificationsAssignmentOverdueOn)
    public static let assignmentOverdueMinute = SettingItem(
        "notifications.assignmentOverdue.minute", .time(hours: 0...23), .number(10 * 60), place: .row(.assignmentAlerts),
        name: .settingItemNotificationsAssignmentOverdueMinute, switchedBy: assignmentOverdue)
    public static let examDayBefore = SettingItem(
        "notifications.examDayBefore.on", .toggle, true, place: .row(.examAlerts), name: .settingItemNotificationsExamDayBeforeOn)
    public static let examDayBeforeMinute = SettingItem(
        "notifications.examDayBefore.minute", .time(hours: 0...23), .number(21 * 60), place: .row(.examAlerts),
        name: .settingItemNotificationsExamDayBeforeMinute, switchedBy: examDayBefore)
    public static let examMorning = SettingItem(
        "notifications.examMorning.on", .toggle, true, place: .row(.examAlerts), name: .settingItemNotificationsExamMorningOn)
    public static let examMorningMinute = SettingItem(
        "notifications.examMorning.minute", .time(hours: 0...23), .number(8 * 60), place: .row(.examAlerts),
        name: .settingItemNotificationsExamMorningMinute, switchedBy: examMorning)
    public static let attendance = SettingItem(
        "notifications.attendance.on", .toggle, true, place: .row(.attendanceAlerts), name: .settingItemNotificationsAttendanceOn)

    public static let backupEnabled = SettingItem(
        "backup.enabled", .toggle, true, place: .row(.autoBackup), name: .settingItemBackupEnabled)
    public static let backupDailyDays = SettingItem(
        "backup.dailyDays", .positive, 30, place: .row(.autoBackup), name: .settingItemBackupDailyDays, unit: .days)
    public static let backupFolder = SettingItem(
        "backup.folder", .text, "~/Backups/Folio/auto", place: .own(.backup), name: .settingItemBackupFolder)

    public static let noteRules = SettingItem(
        "noteRules", .prose,
        .string(
            """
            - 정의는 전제, 조건, 결론 순서로 쓴다.
            - 수학적 진술은 영어와 기호로, 설명은 한국어로 쓴다.
            - display 수식은 하나씩 나눠 쓴다.
            """), place: .row(.noteRules), name: .settingItemNoteRules)
    public static let newNoteMath = SettingItem(
        "newNoteMath", .choice(MathSyntax.allCases.map(\.rawValue)), .string(MathSyntax.asciimath.rawValue), place: .row(.newNote),
        name: .settingItemNewNoteMath, options: MathSyntax.allCases.map { Option(value: $0.rawValue, name: $0.name) })
    public static let noteTemplates = SettingItem("noteTemplates", .custom, [:], place: .own(.notes), name: .settingItemNoteTemplates)
    public static let mathSnippets = SettingItem(
        "mathSnippets", .custom, .null, optional: true, place: .own(.notes), name: .settingItemMathSnippets)
    public static let asciiMathSnippets = SettingItem(
        "asciiMathSnippets", .custom, .null, optional: true, place: .own(.notes), name: .settingItemAsciiMathSnippets)

    // 수업 시작은 고른 것에 따라 행이 나타나고 그림이 바뀌는 카드 하나라서 수업 탭이 따로 그린다.
    public static let classRecording = choice("classStart.recording", ClassStartSettings.Recording.off, .settingItemClassStartRecording)
    public static let classRecordingOffset = SettingItem(
        "classStart.recordingOffsetMinutes", .number(-60...60), 0, place: .own(.classes),
        name: .settingItemClassStartRecordingOffsetMinutes)
    public static let classStopsRecording = SettingItem(
        "classStart.stopsRecording", .toggle, false, place: .own(.classes), name: .settingItemClassStartStopsRecording)
    public static let classStopAfter = SettingItem(
        "classStart.stopAfterMinutes", .number(-60...60), 0, place: .own(.classes), name: .settingItemClassStartStopAfterMinutes)
    public static let classRoughNote = choice("classStart.roughNote", ClassStartSettings.RoughNote.off, .settingItemClassStartRoughNote)
    public static let classRoughNotePlace = choice(
        "classStart.roughNotePlace", ClassStartSettings.Place.here, .settingItemClassStartRoughNotePlace)
    public static let classLecture = choice("classStart.lecture", ClassStartSettings.Lecture.off, .settingItemClassStartLecture)
    public static let classLecturePlace = choice(
        "classStart.lecturePlace", ClassStartSettings.Place.beside, .settingItemClassStartLecturePlace)
    public static let classOpenIn = choice("classStart.openIn", ClassStartSettings.OpenIn.splitTab, .settingItemClassStartOpenIn)
    public static let classAllLectures = SettingItem(
        "classStart.allLectures", .toggle, false, place: .own(.classes), name: .settingItemClassStartAllLectures)
    public static let classResumesLecture = SettingItem(
        "classStart.resumesLecture", .toggle, true, place: .own(.classes), name: .settingItemClassStartResumesLecture)
    public static let classScreen = choice("classStart.screen", ClassStartSettings.Screen.notify, .settingItemClassStartScreen)
    // 배치 목록과 함께 일반 탭의 칸 배치 묶음에서 고른다.
    public static let classPreset = SettingItem(
        "classStart.preset", .text, .null, optional: true, place: .own(.general), name: .settingItemClassStartPreset)
    public static let classCourseOff = SettingItem(
        "classStart.courseOff", .custom, [:], place: .own(.classes), name: .settingItemClassStartCourseOff)

    public static let sidebar = SettingItem("sidebar", .custom, encoded(SidebarOrder()), place: .outside, name: .settingItemSidebar)
    public static let lmsKnown = SettingItem("lms.known", .custom, [], place: .outside, name: .settingItemLmsKnown)
    public static let lmsHandled = SettingItem("lms.handled", .custom, [], place: .outside, name: .settingItemLmsHandled)
    public static let lmsRooms = SettingItem("lms.rooms", .custom, [:], place: .outside, name: .settingItemLmsRooms)
    public static let lmsSyncMinutes = SettingItem(
        "lms.syncMinutes", .number(5...1440), 30, place: .row(.lmsSync), name: .settingItemLmsSyncMinutes, unit: .minutes, step: 5)
    public static let assignmentKinds = SettingItem(
        "assignmentKinds", .custom, .null, optional: true, place: .outside, name: .settingItemAssignmentKinds)

    private static func choice<T: RawRepresentable & CaseIterable>(_ key: String, _ fallback: T, _ name: LocalizedStringResource)
        -> SettingItem where T.RawValue == String
    {
        SettingItem(key, .choice(T.allCases.map(\.rawValue)), .string(fallback.rawValue), place: .own(.classes), name: name)
    }

    // 차례가 설정 화면의 행 차례이자 `settings show`의 차례다.
    public static let all: [SettingItem] = [
        dayBoundary, idleMinutes, panePresets, classPreset,
        todayExamDays, assignmentUrgentDays, assignmentSoonDays, examUrgentDays, examSoonDays, examNearDays,
        dueMinute, examStartMinute, examMinutes,
        gradesUnlockMinutes, staffMailDomain, studentMailDomain,
        studyReadyPercent, studyMinProblems, studyMockMinutes, studyPlanShownDays, studyAutoExtract, studyCoverName,
        assignmentDue, assignmentLeadHours, assignmentOverdue, assignmentOverdueMinute, examDayBefore, examDayBeforeMinute, examMorning,
        examMorningMinute, attendance,
        backupEnabled, backupDailyDays, backupFolder,
        noteRules, newNoteMath, noteTemplates, mathSnippets, asciiMathSnippets, callouts,
        classMinutes, classStartMinute, sessionStartMinute,
        classRecording, classRecordingOffset, classStopsRecording, classStopAfter, classRoughNote, classRoughNotePlace,
        classLecture, classLecturePlace, classOpenIn, classAllLectures, classResumesLecture, classScreen, classCourseOff,
        sidebar, lmsKnown, lmsHandled, lmsRooms, lmsSyncMinutes, assignmentKinds,
    ]
}
