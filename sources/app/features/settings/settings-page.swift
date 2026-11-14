import FolioDomain
import Foundation

extension AppLink.SettingsPage: Identifiable {
    public var id: Self { self }
    static let storageKey = "settingsTab"

    var label: String {
        switch self {
        case .general: String(localized: .settingsTabGeneral)
        case .record: String(localized: .settingsTabRecord)
        case .classes: String(localized: .settingsTabClass)
        case .notes: String(localized: .settingsTabNotes)
        case .review: String(localized: .settingsTabReview)
        case .notifications: String(localized: .settingsTabNotifications)
        case .claude: "Claude"
        case .lms: "LMS"
        case .backup: String(localized: .settingsTabBackup)
        case .about: String(localized: .settingsTabAbout)
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .record: "graduationcap"
        case .classes: "display"
        case .notes: "doc.text"
        case .review: "repeat"
        case .notifications: "bell"
        case .claude: "sparkle"
        case .lms: "link"
        case .backup: "externaldrive"
        case .about: "info.circle"
        }
    }

    var run: Int {
        switch self {
        case .general, .record: 0
        case .classes, .notes, .review: 1
        case .notifications, .claude, .lms, .backup, .about: 2
        }
    }

    // 예전에는 기억한 탭을 한국어 이름으로 저장했다. 주소의 옛 탭 이름은 `AppLink.SettingsPage(rawValue:)`가 읽는다.
    static let storedLabels: [String: AppLink.SettingsPage] = [  // strings: data, read back from settings
        "내 정보": .record, "평어": .record, "녹음": .classes, "일반": .general, "알림": .notifications, "백업": .backup,
        "노트": .notes, "Claude": .claude, "앱 정보": .about,
    ]

    static var remembered: AppLink.SettingsPage {
        guard let stored = UserDefaults.standard.string(forKey: storageKey) else { return .general }
        return AppLink.SettingsPage(rawValue: stored) ?? storedLabels[stored] ?? .general
    }
}
