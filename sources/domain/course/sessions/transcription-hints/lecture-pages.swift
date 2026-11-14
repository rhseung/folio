import Foundation

public struct LecturePages: Codable, Sendable, Equatable {
    public var path: String
    public var first: Int?
    public var last: Int?
    public var materialId: UUID?

    public init(path: String, first: Int? = nil, last: Int? = nil, materialId: UUID? = nil) {
        self.path = path
        self.first = first
        self.last = last
        self.materialId = materialId
    }
}
