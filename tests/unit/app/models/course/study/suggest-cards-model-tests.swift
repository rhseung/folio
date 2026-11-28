import FolioActions
import FolioDomain
import Foundation
import Testing

@testable import Folio

// 카드 만들기는 재료를 하나 고른다. 정리 노트에서 열면 그 노트가 재료이고, 렉처 쪽과 교재는 단원에 나눈 쪽 구간이 있어야 고를 수 있다.
@MainActor
struct SuggestCardsModelTests {
    @Test func aNoteIsTheMaterialWhenOpenedBesideIt() throws {
        let workspace = try fixtureWorkspace()
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let note = try #require(
            workspace.run(NoteAdd(course: graphTheory, title: "기말 02 홀의 정리", kind: .unit, body: "# 홀의 정리\n", units: [unit]))?.made)
        let course = try #require(workspace.course(graphTheory))
        let made = try #require(course.file.units.first { $0.id == unit })

        let model = SuggestCardsModel(workspace: workspace, course: course, unit: made, note: note)
        #expect(model.title == "기말 02 홀의 정리 · 카드 제안" && model.material == .note && model.kinds == .both)
        #expect(model.choices.map(\.material) == [.note, .lecture, .textbook])
        #expect(model.choices.map(\.isAvailable) == [true, false, false])
        #expect(model.choices.map(\.detail) == ["기말 02 홀의 정리", "단원에 나눈 쪽 없음", "단원에 나눈 쪽 없음"])
        #expect(model.kindOptions.map(\.1) == ["앞뒤", "참거짓", "둘 다"])
        #expect(SuggestCardsModel.Kinds.allCases.map(\.kinds) == [[.flip], [.trueFalse], [.flip, .trueFalse]])
        // 테스트는 Claude에 닿지 않으므로 만들 수 없다.
        #expect(!model.hasKey && !model.canConfirm)
    }

    @Test func pagesSplitToTheUnitAreAMaterial() throws {
        let workspace = try fixtureWorkspace()
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        workspace.run(MaterialTrack(course: graphTheory))
        let slides = try #require(workspace.course(graphTheory)?.file.materials.first { $0.path == "Lectures/05_Matchings.pdf" })
        workspace.run(UnitPagesAdd(course: graphTheory, unit: unit, material: slides.id, first: 3, last: 9))
        let course = try #require(workspace.course(graphTheory))
        let made = try #require(course.file.units.first { $0.id == unit })

        // 단원에서 열었고 단원에 이은 노트가 없으면 쪽 구간이 있는 재료가 먼저 골라진다.
        let model = SuggestCardsModel(workspace: workspace, course: course, unit: made)
        #expect(model.title == "매칭 · 카드 제안" && model.material == .lecture)
        #expect(model.choices.map(\.isAvailable) == [false, true, false])
        #expect(model.choices.map(\.detail) == ["단원에 이은 노트 없음", "05_Matchings.pdf 3–9쪽", "단원에 나눈 쪽 없음"])
    }
}
