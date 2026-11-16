import Foundation

// MARK: Splitting a file

public struct LectureCut: Codable, Sendable, Hashable {
    public var unit: UUID
    public var title: String?
    public var parent: UUID?
    public var firstPage: Int
    public var lastPage: Int

    public init(unit: UUID, title: String? = nil, parent: UUID? = nil, firstPage: Int, lastPage: Int) {
        self.unit = unit
        self.title = title
        self.parent = parent
        self.firstPage = firstPage
        self.lastPage = lastPage
    }
}
