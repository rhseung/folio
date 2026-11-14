import Foundation

public struct AnyItems<Doc: Sendable>: Sendable {
    let kind: ObjectIdentifier
    let type: String
    let noun: String
    let all: @Sendable (Doc) -> [(id: UUID, name: String)]
    let checks: @Sendable (Doc, ModelIndex<Doc>) -> [Violation]
    let delete: @Sendable (inout Doc, UUID) -> Void
    let refs: [AnyRef<Doc>]
}
