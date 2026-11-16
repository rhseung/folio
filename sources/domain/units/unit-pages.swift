import Foundation

public struct UnitPages: Codable, Sendable, Hashable {
    public var materialId: UUID
    public var firstPage: Int
    public var lastPage: Int

    public init(materialId: UUID, firstPage: Int, lastPage: Int) {
        self.materialId = materialId
        self.firstPage = firstPage
        self.lastPage = lastPage
    }

    public var pages: ClosedRange<Int> { min(firstPage, lastPage)...max(firstPage, lastPage) }
}
