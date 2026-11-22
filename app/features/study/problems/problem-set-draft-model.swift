import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ProblemSetDraftModel {
    let workspace: Workspace
    let course: LoadedCourse
    var title = ""
    var source = ProblemSource.exercise
    var problemId: UUID?
    var solutionId: UUID?
    var numbers = ""
    var unitIds: [UUID] = []

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        self.course = course
    }

    private var pdfs: [FolioDomain.Material] {
        course.file.materials.filter { $0.isPDF && $0.status != .ignored }.sorted { $0.path < $1.path }
    }

    var pdfOptions: [SelectOption<UUID?>] {
        [SelectOption(id: UUID?.none, label: String(localized: .commonNone))]
            + pdfs.map { SelectOption(id: Optional($0.id), label: ($0.path as NSString).lastPathComponent, detail: $0.path, isFile: true) }
    }

    var sourceOptions: [(ProblemSource, String)] { ProblemSource.allCases.filter { $0 != .claude }.map { ($0, $0.label) } }

    var unitOptions: [SelectOption<UUID>] {
        UnitTree.outline(course.file.units).map { SelectOption(id: $0.unit.id, label: $0.unit.title, depth: $0.depth) }
    }

    private var parsed: [String] { ProblemSet.numbers(from: numbers) }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    var canAdd: Bool { !trimmedTitle.isEmpty && !parsed.isEmpty }
    var sheetDetail: String? { pdfs.isEmpty ? String(localized: .problemSetNoPdfs) : nil }
    var numbersDetail: String {
        parsed.isEmpty ? String(localized: .problemSetNumbersExample) : String(localized: .problemsCount(parsed.count))
    }

    func add() -> Bool {
        let problems = parsed.map { Problem(number: $0, unitIds: unitIds) }
        return workspace.run(
            ProblemSetAdd(
                course: course.id, title: trimmedTitle, source: source, material: problemId, solution: solutionId, problems: problems))
            != nil
    }
}
