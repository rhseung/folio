import FolioCore
import Foundation

// PDF 보기에서 한 쪽에 `Recording.pageDwell`보다 오래 머문 기록이다. 단원의 렉처에서 본 쪽을 센다.
public struct PageViewEvent: LogEvent, Equatable {
    public static let type = "page_view"
    public var materialId: UUID
    public var page: Int

    public init(materialId: UUID, page: Int) {
        self.materialId = materialId
        self.page = page
    }
}
