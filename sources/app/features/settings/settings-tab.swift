import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

// raw value가 `folio://settings/<탭>` 주소의 탭 이름이다.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, record, classes = "class", notes, review, notifications, claude, lms, backup, about
    var id: Self { self }
    static let storageKey = "settingsTab"

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
}
