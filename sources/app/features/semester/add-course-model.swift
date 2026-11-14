import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class AddCourseModel {
    let workspace: Workspace
    let semester: Semester
    var title = ""
    var codeId: UUID?
    var number = ""
    var credits: Double? = 3
    var mode: GradingMode = .relative

    init(workspace: Workspace, semester: Semester) {
        self.workspace = workspace
        self.semester = semester
    }

    var codes: [CourseCode] { workspace.catalog.codes.sorted { $0.prefix < $1.prefix } }

    var folder: String? {
        let prefix = codes.first { $0.id == codeId }?.prefix ?? ""
        return StandardLayout.courseFolderName(prefix: prefix, number: number, title: title)
    }

    var disabled: Bool { folder == nil || codeId == nil || (credits ?? -1) < 0 }

    var note: String { folder.map { String(localized: .semesterFolderNote($0)) } ?? String(localized: .semesterAddCourseHint) }

    func add() -> UUID? {
        guard let codeId, let credits else { return nil }
        return workspace.run(CourseAdd(code: codeId, number: number, title: title, credits: credits, mode: mode, semester: semester.id))?
            .made
    }
}
