import FolioDomain
import FolioStorage
import SwiftUI

struct MaterialSheet: View {
    @State private var model: MaterialsModel
    let material: UUID

    init(workspace: Workspace, course: LoadedCourse, request: MaterialSheetRequest) {
        _model = State(initialValue: MaterialsModel(workspace: workspace, course: course, moves: request.moves ?? MoveUndo()))
        material = request.material
    }

    var body: some View { MaterialLinksEditor(model: model, materialId: material) }
}
