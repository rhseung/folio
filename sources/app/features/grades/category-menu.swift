import FolioDomain
import SwiftUI

struct CategoryMenu: View {
    // 과목 편집기가 넘길 workspace 없이 이 메뉴를 만들므로 environment에서 읽는다.
    @Environment(Workspace.self) private var workspace
    @Binding var selection: [UUID]
    var course: Course?

    var body: some View {
        SearchMultiSelect(
            selection: $selection,
            options: RequirementsModel.categoryOptions(workspace.requirementCatalog, selection: selection, course: course),
            placeholder: String(localized: .requirementsPickCategory))
    }
}
