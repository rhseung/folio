import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ProblemEditorModel {
    let workspace: Workspace
    let course: LoadedCourse
    let setId: UUID
    let original: Problem
    var text: String
    var format: ProblemFormat
    // 객관식 보기는 한 줄에 하나다.
    var options: String
    var answer: String
    var solution: String
    var page: String
    var solutionPage: String
    var unitIds: [UUID]
    var pending: PendingAction?

    init(workspace: Workspace, course: LoadedCourse, set: UUID, problem: Problem) {
        self.workspace = workspace
        self.course = course
        setId = set
        original = problem
        text = problem.text
        format = problem.format
        options = problem.format == .choice ? problem.options.joined(separator: "\n") : ""
        answer = problem.answer ?? ""
        solution = problem.solution ?? ""
        page = problem.page.map(String.init) ?? ""
        solutionPage = problem.solutionPage.map(String.init) ?? ""
        unitIds = problem.unitIds
    }

    var title: String {
        let set = course.file.problemSets.first { $0.id == setId }
        return String(localized: .problemsNumbered(set?.title ?? "", original.number))
    }

    var formatOptions: [(ProblemFormat, String)] { ProblemFormat.allCases.map { ($0, $0.label) } }
    var answerOptions: [(String, String)] {
        let values = format == .trueFalse ? Problem.trueFalseOptions : choiceList
        return [("", String(localized: .commonNone))] + values.map { ($0, $0) }
    }
    var choiceList: [String] { options.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    var picksAnswer: Bool { format == .trueFalse || format == .choice }
    var hasKeyField: Bool { format != .written }

    var unitOptions: [SelectOption<UUID>] {
        UnitTree.outline(course.file.units).map { SelectOption(id: $0.unit.id, label: $0.unit.title, depth: $0.depth) }
    }

    func confirm() -> Bool {
        var p = original
        p.text = text
        p.format = format
        p.options = format == .trueFalse ? Problem.trueFalseOptions : format == .choice ? choiceList : []
        let key = answer.trimmingCharacters(in: .whitespaces)
        p.answer = format == .written || key.isEmpty ? nil : key
        p.solution = solution.isEmpty ? nil : solution
        p.page = Int(page)
        p.solutionPage = Int(solutionPage)
        p.unitIds = unitIds
        return workspace.run(ProblemSave(course: course.id, set: setId, problems: [p])) != nil
    }

    func remove() { pending = workspace.ask(ProblemRemove(course: course.id, set: setId, problem: original.id)) }
}
