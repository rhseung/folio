import Foundation

// 설정 화면의 한 묶음(제목 아래 카드 하나)이다. 묶음의 행은 `SettingItem.all`에서 이 묶음에 놓인 항목을 차례대로 읽는다.
public enum SettingGroup: String, CaseIterable, Sendable {
    case day, deadlines, school, classTime, newNote, study, assignmentAlerts, examAlerts, attendanceAlerts, autoBackup, noteRules, lmsSync

    public var page: AppLink.SettingsPage {
        switch self {
        case .day, .deadlines: .general
        case .school: .record
        case .classTime: .classes
        case .newNote: .notes
        case .study: .study
        case .assignmentAlerts, .examAlerts, .attendanceAlerts: .notifications
        case .autoBackup: .backup
        case .noteRules: .claude
        case .lmsSync: .lms
        }
    }

    // 탭 제목이 이미 말하는 묶음(공부)과 행 이름이 제목인 묶음(노트 작성 규칙)은 제목을 두지 않는다.
    public var name: LocalizedStringResource? {
        switch self {
        case .day: .settingGroupDay
        case .deadlines: .settingGroupDeadlines
        case .school: .settingGroupSchool
        case .classTime: .settingGroupClassTime
        case .newNote: .settingGroupNewNote
        case .assignmentAlerts: .settingGroupAssignmentAlerts
        case .examAlerts: .settingGroupExamAlerts
        case .attendanceAlerts: .settingGroupAttendanceAlerts
        case .autoBackup: .settingGroupAutoBackup
        case .lmsSync: .settingGroupLmsSync
        case .study, .noteRules: nil
        }
    }

    public var rows: [SettingItem] { SettingItem.all.filter { $0.place == .row(self) } }
    public var more: [SettingItem] { SettingItem.all.filter { $0.place == .more(self) } }
}
