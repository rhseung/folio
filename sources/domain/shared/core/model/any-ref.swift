import Foundation

struct AnyRef<Doc: Sendable>: Sendable {
    let target: ObjectIdentifier
    let onDelete: OnDelete
    let holders: @Sendable (Doc, UUID) -> [UUID]
    let values: @Sendable (Doc, UUID) -> [UUID]
    let detach: @Sendable (inout Doc, UUID, UUID?) -> Void
}
