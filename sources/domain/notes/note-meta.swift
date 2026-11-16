import Foundation

public struct NoteMeta: Equatable, Sendable {
    public var id: UUID?
    public var kind: NoteKind
    public var sessionIds: [UUID]
    public var unitIds: [UUID]
    public var examId: UUID?
    public var tags: [String]
    public var math: MathSyntax

    public init(
        id: UUID? = UUID(), kind: NoteKind = .free, sessionId: UUID? = nil, unitIds: [UUID] = [], examId: UUID? = nil, tags: [String] = [],
        math: MathSyntax = .latex
    ) {
        self.id = id
        self.kind = kind
        self.sessionIds = sessionId.map { [$0] } ?? []
        self.unitIds = unitIds
        self.examId = examId
        self.tags = tags
        self.math = math
    }

    public var sessionId: UUID? {
        get { sessionIds.first }
        set { sessionIds = newValue.map { [$0] } ?? [] }
    }
}
