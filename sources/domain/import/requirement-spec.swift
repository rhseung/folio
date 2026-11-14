import Foundation

public struct RequirementSpec: Codable, Sendable, Equatable {
    public var name: String
    public var group: String
    public var isMajor: Bool
    public var parent: String?
    public var minCredits: Double?
    public var maxCredits: Double?
    public var minCount: Int?
    public var maxSharedCredits: Double?
    public var rule: String?
    public var renamedFrom: String?
    public var program: String?
}
