import Foundation

struct RefInfo<E>: Sendable {
    let target: ObjectIdentifier
    let onDelete: OnDelete
    let points: @Sendable (E) -> [UUID]
    let detach: @Sendable (inout E, UUID, UUID?) -> Void
}
