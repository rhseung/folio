import Foundation

public struct ReviewState: Sendable, Equatable {
    public var unitId: UUID
    public var step: Int
    public var due: LocalDate?
    public var settled: Bool
    public var writeNoteFirst: Bool

    public init(unitId: UUID, step: Int, due: LocalDate?, settled: Bool, writeNoteFirst: Bool) {
        self.unitId = unitId
        self.step = step
        self.due = due
        self.settled = settled
        self.writeNoteFirst = writeNoteFirst
    }

    public func isDue(on today: LocalDate) -> Bool { due.map { $0 <= today } ?? false }
}
