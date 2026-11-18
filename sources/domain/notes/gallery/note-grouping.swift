import Foundation

public enum NoteGrouping: String, CaseIterable, Codable, Sendable {
    case date, kind, week, unit, exam, folder, tag, none

    // 종류마다 고를 수 있는 묶기다. 첫째가 기본값이다.
    public static func options(for group: NoteGroup?) -> [NoteGrouping] {
        switch group {
        case nil: [.date, .kind, .none]
        case .classes: [.week, .unit, .date]
        case .units: [.unit]
        case .exams: [.exam]
        case .free: [.folder, .tag, .date]
        }
    }
}
