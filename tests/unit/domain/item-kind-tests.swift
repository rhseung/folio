import FolioDomain
import Testing

struct ItemKindTests {
    @Test func everyLinkKindWithAnIDHasOneItemKind() {
        for kind in AppLink.Kind.allCases where !kind.isPlace {
            #expect(ItemKind(link: kind)?.link == kind, "\(kind)")
        }
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
