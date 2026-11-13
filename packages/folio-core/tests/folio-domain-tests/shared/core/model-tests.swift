@testable import FolioDomain
import Foundation
import Testing

private struct Group: Identifiable, Sendable, Equatable {
    var id = UUID()
    var name: String
    var parentId: UUID?
    var tagIds: [UUID] = []
}

private struct Item: Identifiable, Sendable, Equatable {
    var id = UUID()
    var title: String
    var groupId: UUID
    var tagId: UUID?
    var ownerId: UUID?
}

private struct Tag: Identifiable, Sendable, Equatable {
    var id = UUID()
    var name: String
    var groupIds: [UUID] = []
}

private struct Owner: Identifiable, Sendable, Equatable {
    var id = UUID()
    var name: String
}

private struct Shelf: Document, Equatable {
    var groups: [Group] = []
    var items: [Item] = []
    var tags: [Tag] = []
    var owners: [Owner] = []

    static let model = Model<Shelf>(place: "이 선반에") {
        Items(\.groups, noun: "묶음", name: \.name) {
            Ref(\.parentId, to: Group.self, onDelete: .reparent)
            Refs(\.tagIds, to: Tag.self, onDelete: .nullify)
        }
        Items(\.items, noun: "항목", name: \.title) {
            NonEmpty(\.title, "항목 제목이 비었습니다")
            Ref(\.groupId, to: Group.self, onDelete: .cascade)
            Ref(\.tagId, to: Tag.self, onDelete: .nullify)
            Ref(\.ownerId, to: Owner.self, as: "주인", onDelete: .restrict)
        }
        Items(\.tags, noun: "태그", name: \.name) {
            Refs(\.groupIds, to: Group.self, onDelete: .nullify)
        }
        Items(\.owners, noun: "주인", name: \.name)
        Pair(\.groups, \.tagIds, \.tags, \.groupIds)
    }
}

struct ModelTests {
    private func shelf() -> (Shelf, top: Group, child: Group, tag: Tag, owner: Owner, item: Item) {
        var top = Group(name: "위")
        let tag = Tag(name: "급함", groupIds: [top.id])
        top.tagIds = [tag.id]
        let child = Group(name: "아래", parentId: top.id)
        let owner = Owner(name: "나")
        let item = Item(title: "숙제", groupId: top.id, tagId: tag.id)
        return (Shelf(groups: [top, child], items: [item], tags: [tag], owners: [owner]), top, child, tag, owner, item)
    }

    @Test func aWellFormedDocumentHasNoViolations() {
        #expect(shelf().0.violations.isEmpty)
    }

    @Test func removingAGroupTakesItsItemsAndReparentsItsChildren() throws {
        var (s, top, child, tag, _, _) = shelf()
        let grandchild = Group(name: "손주", parentId: child.id)
        s.groups.append(grandchild)
        try s.remove(Group.self, child.id)
        #expect(s.groups.first { $0.id == grandchild.id }?.parentId == top.id)

        try s.remove(Group.self, top.id)
        #expect(s.items.isEmpty)
        #expect(s.groups.map(\.id) == [grandchild.id])
        #expect(s.groups[0].parentId == nil)
        #expect(s.tags.first { $0.id == tag.id }?.groupIds == [])
        #expect(s.violations.isEmpty)
    }

    @Test func removingATagClearsWhatPointsAtIt() throws {
        var (s, _, _, tag, _, item) = shelf()
        try s.remove(Tag.self, tag.id)
        #expect(s.items.first { $0.id == item.id }?.tagId == nil)
        #expect(s.groups.allSatisfy { $0.tagIds.isEmpty })
        #expect(s.violations.isEmpty)
    }

    @Test func anOwnerInUseCannotBeRemoved() throws {
        var (s, _, _, _, owner, _) = shelf()
        s.items[0].ownerId = owner.id
        #expect(throws: ModelError.rule("항목 '숙제'가 가리키고 있어 주인 '나'를 지울 수 없습니다")) {
            try s.remove(Owner.self, owner.id)
        }
        s.items[0].ownerId = nil
        try s.remove(Owner.self, owner.id)
        #expect(s.owners.isEmpty)
    }

    @Test func aOneSidedLinkIsAViolation() {
        var (s, _, _, _, _, _) = shelf()
        s.tags[0].groupIds = []
        #expect(s.violations.map(\.message) == ["묶음 '위'와 태그 '급함'의 연결이 한쪽에만 있습니다"])
    }

    @Test func missingTargetsAndDuplicatesAreNamedWithTheRightParticle() {
        var (s, _, _, _, _, item) = shelf()
        let ghost = UUID()
        s.items[0].ownerId = ghost
        s.items[0].groupId = ghost
        s.items.append(item)
        let messages = Set(s.violations.map(\.message))
        #expect(messages.contains("항목 '숙제'의 주인이 이 선반에 없습니다: \(ghost)"))
        #expect(messages.contains("항목 '숙제'의 묶음이 이 선반에 없습니다: \(ghost)"))
        #expect(messages.contains("항목 ID가 겹칩니다: \(item.id)"))
    }

    @Test func onlyNewViolationsCount() {
        let (s, _, _, _, _, _) = shelf()
        var broken = s
        broken.items[0].title = ""
        var edited = broken
        edited.items[0].tagId = nil
        #expect(Shelf.model.newViolation(before: broken, after: edited) == nil)
        #expect(Shelf.model.newViolation(before: s, after: broken)?.message == "항목 제목이 비었습니다")
    }

    @Test func updateAndRemoveNameWhatTheyCouldNotFind() {
        var (s, _, _, _, _, _) = shelf()
        #expect(throws: ModelError.notFound("태그를 찾지 못했습니다")) { try s.update(\.tags, UUID()) { _ in } }
        #expect(throws: ModelError.notFound("묶음을 찾지 못했습니다")) { try s.remove(Group.self, UUID()) }
    }

    @Test func particlesFollowTheLastSyllable() {
        #expect(Korean.subject("시험") == "시험이")
        #expect(Korean.subject("과제") == "과제가")
        #expect(Korean.object("항목") == "항목을")
        #expect(Korean.object("ABC") == "ABC를")
    }
}
