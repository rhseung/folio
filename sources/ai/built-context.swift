import FolioDomain
import Foundation

public struct BuiltContext: Sendable, Equatable {
    public var system: [ContentBlock]
    public var userBlocks: [ContentBlock]
    public var included: [ContextItem]
    public var dropped: [ContextItem]
}
