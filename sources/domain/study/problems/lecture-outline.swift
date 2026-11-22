import Foundation

// 문제를 뽑을 때 Claude에게 주는 렉처의 쪽 제목이다. 단원의 렉처 쪽 구간에 든 쪽만 담는다. Claude가 문제마다 관련 렉처 쪽을
// 이 쪽들에서 고르고, 앱은 그 쪽이 든 단원에 문제를 잇는다.
public struct LectureOutline: Sendable, Equatable {
    public struct Lecture: Sendable, Equatable {
        public var materialId: UUID
        public var name: String
        public var pages: [Page]

        public init(materialId: UUID, name: String, pages: [Page]) {
            self.materialId = materialId
            self.name = name
            self.pages = pages
        }
    }

    public struct Page: Sendable, Equatable {
        public var number: Int
        public var title: String?

        public init(number: Int, title: String?) {
            self.number = number
            self.title = title
        }
    }

    public var lectures: [Lecture]

    public init(lectures: [Lecture] = []) { self.lectures = lectures }

    // 렉처마다 읽을 쪽이다. 단원의 쪽 구간을 합친다.
    public static func pages(of units: [Unit]) -> [UUID: [Int]] {
        var out: [UUID: Set<Int>] = [:]
        for unit in units {
            for range in unit.lecturePages { out[range.materialId, default: []].formUnion(range.pages) }
        }
        return out.mapValues { $0.sorted() }
    }
}
