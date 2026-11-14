import Foundation

public enum ClassReview: Hashable, Sendable, CaseIterable {
    case needed, notNeeded, writing, written

    public var choices: [ClassReview] {
        switch self {
        case .needed, .notNeeded: [.needed, .notNeeded]
        case .writing, .written: [.writing, .written]
        }
    }

    public var isChecked: Bool { self == .notNeeded || self == .written }

    public var toggled: ClassReview {
        switch self {
        case .needed: .notNeeded
        case .notNeeded: .needed
        case .writing: .written
        case .written: .writing
        }
    }

    public var skipsReview: Bool? {
        switch self {
        case .needed: false
        case .notNeeded: true
        case .writing, .written: nil
        }
    }

    public var reviewUnfinished: Bool? {
        switch self {
        case .writing: true
        case .written: false
        case .needed, .notNeeded: nil
        }
    }
}
