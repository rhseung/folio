import Foundation

public struct StudentProgram: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case major, doubleMajor, minor, intensive
    }

    public var codeId: UUID
    public var kind: Kind

    public init(codeId: UUID, kind: Kind) {
        self.codeId = codeId
        self.kind = kind
    }
}
