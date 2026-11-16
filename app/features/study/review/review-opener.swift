import FolioDomain
import FolioStorage
import SwiftUI

struct ReviewOpener<Label: View>: View {
    @Environment(Workspace.self) private var workspace
    let courseId: UUID
    let unitId: UUID
    var then: [ReviewView.Item] = []
    @ViewBuilder var label: Label
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            label.contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .sheet(isPresented: $open) { ReviewView(workspace: workspace, courses: [.init(courseId: courseId, unitId: unitId)] + then) }
    }
}
