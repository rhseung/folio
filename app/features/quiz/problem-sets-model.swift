import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ProblemSetDraftModel {
    let workspace: Workspace
    let course: LoadedCourse
    var title = ""
    var problemId: UUID?
    var solutionId: UUID?
    var numbers = ""
    var unitIds: [UUID] = []

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        self.course = course
    }

    var pdfs: [FolioDomain.Material] {
        course.file.materials.filter { !$0.isFolder && $0.status != .ignored && $0.path.lowercased().hasSuffix(".pdf") }.sorted { $0.path < $1.path }
    }

    var pdfOptions: [PickOption<UUID?>] {
        [PickOption(id: UUID?.none, title: String(localized: .commonNone))]
            + pdfs.map { PickOption(id: Optional($0.id), title: ($0.path as NSString).lastPathComponent, detail: $0.path) }
    }

    var parsed: [String] { ProblemSet.numbers(from: numbers) }
    var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    var canAdd: Bool { !trimmedTitle.isEmpty && !parsed.isEmpty }
    var sheetDetail: String? { pdfs.isEmpty ? String(localized: .quizProblemsNoPdfs) : nil }
    var numbersDetail: String {
        let n = parsed.count
        return n == 0 ? String(localized: .quizProblemsNumbersExample) : String(localized: .quizProblemsItems(n))
    }

    func add() {
        var set = ProblemSet(device: workspace.device, at: .now, title: trimmedTitle,
                             problems: parsed.map { ProblemSet.Problem(number: $0, unitIds: unitIds) })
        set.materialId = problemId
        set.solutionMaterialId = solutionId
        workspace.run(ProblemSetSave(course: course.id, set: set))
    }
}
