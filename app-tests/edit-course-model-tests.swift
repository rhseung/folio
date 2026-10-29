import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct EditCourseModelTests {
    func model() throws -> EditCourseModel {
        let workspace = try fixtureWorkspace()
        return EditCourseModel(workspace: workspace, course: try #require(workspace.course(graphTheory)))
    }

    @Test func noCodeMeansNoFolderAndNoSave() throws {
        let model = try model()
        #expect(model.folder == nil)
        #expect(!model.canSave)
        #expect(model.note == "강의 코드와 번호(예: 4207-01), 이름을 넣어야 폴더 이름이 정해집니다")
    }

    @Test func classEndingBeforeItStartsBlocksTheTimesSheet() throws {
        let model = try model()
        #expect(model.timesNote == nil)
        model.schedule = [ClassTime(weekday: 1, startMinute: 11 * 60, endMinute: 10 * 60)]
        #expect(model.badTime)
        #expect(model.timesNote == "수업이 끝나는 시간이 시작 시간보다 늦어야 합니다")
    }

    @Test func pickingTheMainCodeMovesItFirst() throws {
        let model = try model()
        let a = UUID(), b = UUID(), c = UUID()
        model.codes = [a, b, c]
        model.makeMain(c)
        #expect(model.codes == [c, a, b])
        #expect(model.codeDetail == "교차 개설: 첫 코드를 폴더 이름에 씁니다")
    }
}
