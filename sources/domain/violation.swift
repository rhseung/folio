import Foundation

public struct Violation: Hashable, Sendable, CustomStringConvertible {
    public let rule: RuleID
    public let subject: UUID?
    public let message: String

    public init(_ rule: RuleID, subject: UUID?, _ message: String) {
        (self.rule, self.subject, self.message) = (rule, subject, message)
    }

    public static func == (a: Self, b: Self) -> Bool { a.rule == b.rule && a.subject == b.subject }
    public func hash(into h: inout Hasher) {
        h.combine(rule)
        h.combine(subject)
    }
    public var description: String { message }
}
