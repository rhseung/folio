import FolioDomain
import Foundation

// 카드 제안에 사용자가 고른 것이다. 재료의 글(노트 본문, 렉처나 교재의 쪽)은 맥락으로 따로 준다.
public struct CardRequest: Sendable, Equatable {
    // 정리 노트나 단원의 이름이다.
    public var title: String
    public var material: CardMaterial
    public var kinds: [CardKind]
    public var count: Int
    public var existing: [String]
    // 재료가 정리 노트일 때 그 노트의 절이다. 제안된 카드는 이 가운데 하나를 고른다.
    public var sections: [String]

    public init(
        title: String, material: CardMaterial = .note, kinds: [CardKind] = [.flip], count: Int, existing: [String] = [],
        sections: [String] = []
    ) {
        self.title = title
        self.material = material
        self.kinds = kinds.isEmpty ? [.flip] : kinds
        self.count = count
        self.existing = existing
        self.sections = sections
    }
}
