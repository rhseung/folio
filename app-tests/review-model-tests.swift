import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct ReviewModelTests {
    func source(_ name: String, beside: Bool) -> ReviewModel.Source {
        .init(id: .note(URL(filePath: "/\(name).md")), title: name, symbol: "doc.text", beside: beside)
    }

    @Test func aReferenceOpensBesideAndANoteReplacesTheMain() throws {
        let model = ReviewModel(workspace: try fixtureWorkspace(), items: [])
        let review = source("review", beside: false), other = source("other", beside: false), rough = source("rough", beside: true)
        model.sources = [review, other, rough]
        model.main = review.id
        #expect(model.action(for: review) == nil)
        #expect(model.action(for: rough) == "옆에 펼치기")
        #expect(model.action(for: other) == "이 노트로 바꾸기")
        model.pick(rough)
        #expect(model.side == rough.id && model.action(for: rough) == "옆에서 닫기")
        model.pick(rough)
        #expect(model.side == nil)
        model.pick(other)
        #expect(model.main == other.id && model.isShown(other) && !model.isShown(review))
    }

    @Test func aUnitWithoutNotesHasNothingInTheMainPane() throws {
        let workspace = try fixtureWorkspace()
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let model = ReviewModel(workspace: workspace, items: [.init(courseId: graphTheory, unitId: unit)])
        let current = try #require(model.current)
        model.load(course: current.course, unit: current.unit)
        #expect(model.sources.isEmpty && model.mainSource == nil)
        #expect(model.sessionLine(current.course, current.unit) == nil)
        // No past session, so no cycle: the results have no day to show.
        #expect(model.outcomes(now: .now).values.allSatisfy { $0 == " " })
    }

    @Test func recordingMovesThroughTheQueue() throws {
        let workspace = try fixtureWorkspace()
        let a = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let b = try #require(workspace.run(UnitAdd(course: graphTheory, title: "채색"))?.made)
        let model = ReviewModel(workspace: workspace, items: [.init(courseId: graphTheory, unitId: a), .init(courseId: graphTheory, unitId: b)])
        #expect(model.counter == "1 / 2" && !model.isLast)
        model.record(.good)
        model.advance()
        #expect(model.unitId == b && model.isLast && model.counter == "2 / 2")
        #expect(workspace.reviews(of: graphTheory).map(\.event.unitId) == [a])
    }

    @Test func elapsedReadsMinutesAndSeconds() throws {
        let model = ReviewModel(workspace: try fixtureWorkspace(), items: [])
        #expect(model.elapsed(until: model.started.addingTimeInterval(125)) == "2:05")
        #expect(model.elapsed(until: model.started.addingTimeInterval(-5)) == "0:00")
    }
}
