import Foundation

// 문제의 개념을 다시 볼 렉처의 쪽이다. 뽑을 때 Claude가 단원의 쪽 구간에서 고른다.
public struct ProblemPage: Codable, Sendable, Hashable {
    public var materialId: UUID
    public var page: Int

    public init(materialId: UUID, page: Int) {
        self.materialId = materialId
        self.page = page
    }
}
