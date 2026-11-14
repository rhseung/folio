import Foundation

public struct AnyRule<Doc: Sendable>: Sendable {
    let check: @Sendable (Doc, ModelIndex<Doc>) -> [Violation]
}
