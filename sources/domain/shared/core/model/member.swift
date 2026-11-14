import Foundation

// MARK: Members

public struct Member<Doc: Sendable, E: Sendable>: Sendable {
    let check: @Sendable (E, Doc, _ label: String, ModelIndex<Doc>) -> [Violation]
    let ref: RefInfo<E>?
}
