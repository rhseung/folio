import FolioDomain
import Testing

struct ItemKindTests {
    @Test func everyLinkKindWithAnIDHasOneItemKind() {
        // 노트의 카드 칸은 노트 하나에 딸린 보기라서 항목 종류가 없다.
        for kind in AppLink.Kind.allCases where !kind.isPlace && kind != .noteCards {
            #expect(ItemKind(link: kind)?.link == kind, "\(kind)")
        }
        #expect(ItemKind(link: .noteCards) == nil)
    }

    @Test func parentsAreCourseItemsWithoutParents() {
        for kind in ItemKind.allCases {
            guard let parent = kind.parent else { continue }
            #expect(kind.inCourse && parent.inCourse && parent.parent == nil, "\(kind)")
            #expect(!kind.foldsIntoCourse)
        }
    }

    @Test func everyKindHasANoun() {
        for kind in ItemKind.allCases { #expect(!kind.noun.isEmpty && kind.noun != kind.rawValue, "\(kind)") }
    }
}
