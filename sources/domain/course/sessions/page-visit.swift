import Foundation

public struct PageVisit: Codable, Sendable, Equatable {
    public var at: TimeInterval
    public var materialId: UUID
    public var page: Int?

    public init(at: TimeInterval, materialId: UUID, page: Int?) {
        self.at = at
        self.materialId = materialId
        self.page = page
    }
}
