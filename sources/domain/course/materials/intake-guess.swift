import Foundation

public struct IntakeGuess: Equatable, Sendable {
    public enum Why: Equatable, Sendable {
        case named(String)
        case slides(pages: Int)
        case book(pages: Int)

        public var text: String {
            switch self {
            case .named(let words): String(localized: .intakeWhyNamed(words))
            case .slides(let pages): String(localized: .intakeWhySlides(pages))
            case .book(let pages): String(localized: .intakeWhyBook(pages))
            }
        }
    }

    public enum SessionWhy: Equatable, Sendable {
        case week(Int)
        case today
        case latest

        public var text: String {
            switch self {
            case .week(let week): String(localized: .intakeSessionWeek(week))
            case .today: String(localized: .intakeSessionToday)
            case .latest: String(localized: .intakeSessionLatest)
            }
        }
    }

    public var folder: String
    public var why: Why?
    public var session: UUID?
    public var sessionWhy: SessionWhy?

    public init(folder: String, why: Why? = nil, session: UUID? = nil, sessionWhy: SessionWhy? = nil) {
        (self.folder, self.why, self.session, self.sessionWhy) = (folder, why, session, sessionWhy)
    }
}
