import Foundation

public enum WrongStatus: Equatable, Sendable {
    case neverWrong
    case open(since: LocalDate)
    case resolved(on: LocalDate, recheckDue: LocalDate?)
}
