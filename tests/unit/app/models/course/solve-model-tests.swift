import FolioActions
import FolioDomain
import Foundation
import Testing

@testable import Folio

@MainActor
struct SolveModelTests {
    func solvable() throws -> (Workspace, UUID) {
        let workspace = try fixtureWorkspace()
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let problems = ["참", "거짓"].enumerated().map { i, key in
            Problem(number: "\(i + 1)", text: "문제 \(i + 1)", format: .trueFalse, answer: key, unitIds: [unit])
        }
        workspace.run(ProblemSetAdd(course: graphTheory, title: "연습 1", problems: problems))
        return (workspace, unit)
    }

    @Test func aKeyedProblemGradesAtOnceAndOnlyGradedOnesAreLogged() throws {
        let (workspace, unit) = try solvable()
        let model = SolveModel(workspace: workspace, request: SolveRequest(course: graphTheory, units: [unit]))
        #expect(model.phase == .setup && model.picked.count == 2)

        model.start()
        model.choose("참")
        #expect(model.graded?.verdict == .correct && model.graded?.basis == .key)
        model.next()
        model.choose("참")
        #expect(model.graded?.verdict == .wrong)
        model.next()
        #expect(model.phase == .done && model.wrongCount == 1)
        #expect(workspace.study(of: graphTheory)?.allProblems.filter { $0.status.needsWork }.count == 1)

        model.retryWrong()
        #expect(model.phase == .solving && model.current?.problem.number == "2")
    }

    @Test func aSkippedProblemLeavesNoRecord() throws {
        let (workspace, unit) = try solvable()
        let model = SolveModel(workspace: workspace, request: SolveRequest(course: graphTheory, units: [unit]))
        model.start()
        model.next()
        model.next()
        #expect(model.phase == .done && model.unitResults().isEmpty)
        #expect(workspace.study(of: graphTheory)?.allProblems.allSatisfy { $0.attempts.isEmpty } == true)
    }

    @Test func aMockKeepsAnswersUntilItIsHandedIn() throws {
        let (workspace, unit) = try solvable()
        let model = SolveModel(workspace: workspace, request: SolveRequest(course: graphTheory, units: [unit], mode: .mock))
        model.start()
        model.choose("참")
        #expect(model.graded == nil)
        model.next()
        model.back()
        #expect(model.answer == "참")
    }
}
