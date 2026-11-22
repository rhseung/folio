import FolioCore
import Foundation

public struct SameAnswer: StructuredResult, Equatable {
    public var same: Bool

    public static let schema = Schema.object(["same": Schema.boolean])
}
