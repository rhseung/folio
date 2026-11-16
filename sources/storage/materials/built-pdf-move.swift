import FolioDomain
import FolioMarkdown
import Foundation

public struct BuiltPDFMove: Equatable, Sendable {
    public var from: String
    public var to: String
    public var blocked: Bool
}
