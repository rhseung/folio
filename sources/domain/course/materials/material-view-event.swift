import Algorithms
import Foundation

public struct MaterialViewEvent: LogEvent, Equatable {
    public static let type = "material_view"
    public var materialId: UUID
    // 0부터 센 쪽 번호다.
    public var page: Int

    public init(materialId: UUID, page: Int) {
        self.materialId = materialId
        self.page = page
    }
}
