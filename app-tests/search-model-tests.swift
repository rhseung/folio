import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct SearchModelTests {
    func hits() -> [SearchHit] {
        let notes = (1...10).map { SearchItem(kind: .note, courseId: graphTheory, id: UUID(), title: "matching \($0)") }
        let files = (1...2).map { SearchItem(kind: .material, courseId: graphTheory, id: UUID(), title: "matching slides \($0)") }
        return SearchIndex(files + notes).search("matching")
    }

    @Test func eachKindIsCappedUntilItIsChosen() throws {
        let model = SearchModel(workspace: try fixtureWorkspace())
        model.hits = hits()
        let notes = try #require(model.groups.first { $0.kind == .note })
        #expect(notes.hits.count == SearchModel.perKind && notes.more == 2)
        #expect(model.groups.first { $0.kind == .material }?.more == 0)
        model.kind = .note
        #expect(model.groups.first { $0.kind == .note }?.hits.count == 10)
    }

    @Test func arrowsStayInsideTheResults() throws {
        let model = SearchModel(workspace: try fixtureWorkspace())
        model.moveSelection(by: 1)
        #expect(model.selected == 0)
        model.hits = hits()
        model.moveSelection(by: -1)
        #expect(model.selected == 0)
        for _ in 0..<20 { model.moveSelection(by: 1) }
        #expect(model.selected == model.flat.count - 1)
    }

    @Test func aHitOpensItsSectionAndItem() throws {
        let model = SearchModel(workspace: try fixtureWorkspace())
        let hit = try #require(hits().first { $0.item.kind == .note })
        let target = model.target(hit)
        #expect(target.section == .notes && target.noteId == hit.item.id && target.materialId == nil)
    }

    @Test func emptyMessageSaysWhetherToWidenTheFilters() throws {
        let model = SearchModel(workspace: try fixtureWorkspace())
        #expect(model.emptyMessage == "결과가 없습니다")
        model.scope = .course(graphTheory)
        #expect(model.emptyMessage == "결과가 없습니다. 거르는 조건을 넓혀 보세요")
        model.indexing = (1, 3)
        #expect(model.emptyMessage.hasPrefix("아직 색인 중"))
    }

    @Test func snippetsLoseTheirMarkdown() {
        #expect(SearchModel.plain("**굵게** [[링크|별칭]] ![그림](assets/a.png) `x`") == "굵게 링크 그림 x")
        #expect(SearchModel.plain("…0](assets/x.png) ## 제목") == "…0 제목")
    }
}
