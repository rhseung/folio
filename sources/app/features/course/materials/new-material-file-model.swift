import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class NewMaterialFileModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let places: [String]
    var folder: String
    var name = ""

    init(workspace: Workspace, course: LoadedCourse, folder: String?) {
        self.workspace = workspace
        initial = course
        let file = course.file
        var places = NewMaterialFile.places(
            assignments: file.assignments, exams: file.exams,
            assignmentFolders: (try? course.store.assignmentFolders()) ?? [])
        if let folder, !places.contains(folder) { places.append(folder) }
        self.places = places
        self.folder = folder ?? NewMaterialFile.defaultPlace(assignments: file.assignments, places: places) ?? places[0]
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }

    var fileName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.contains(".") ? trimmed : trimmed + ".tex"
    }

    var action: MaterialNew { MaterialNew(course: course.id, folder: folder, name: fileName) }

    var refusal: String? { fileName.isEmpty ? nil : workspace.refusal(action) }
    var canCreate: Bool { !fileName.isEmpty && refusal == nil }

    var folderOptions: [(String, String)] { places.map { ($0, $0) } }

    func create() -> UUID? { workspace.run(action)?.made }
}
