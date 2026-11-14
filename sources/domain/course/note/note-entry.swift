import Foundation

public struct NoteEntry: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var path: String
    public var kind: NoteKind
    public var unitIds: [UUID]
    public var examId: UUID?
    public var tags: [String]
    public var math: MathSyntax
    public var builtHash: String?

    public init(id: UUID, device: DeviceID, at date: Date, path: String, meta: NoteMeta) {
        self.id = id
        createdAt = date
        updatedAt = date
        updatedBy = device
        self.path = path
        kind = meta.kind
        unitIds = []
        tags = []
        math = meta.math
        apply(meta)
    }

    public mutating func apply(_ meta: NoteMeta) {
        kind = meta.kind
        unitIds = meta.kind == .unit ? meta.unitIds : []
        examId = meta.examId
        tags = meta.tags
        math = meta.math
    }
}
