import FolioDomain
import SwiftUI

struct SolveSheet: View {
    @State private var model: SolveModel

    init(workspace: Workspace, request: SolveRequest) { _model = State(initialValue: SolveModel(workspace: workspace, request: request)) }

    var body: some View {
        Group {
            switch model.phase {
            case .setup: SolveSetup(model: model)
            case .solving: SolveRun(model: model)
            case .done: SolveResult(model: model)
            }
        }
        .courseAccent(model.accent)
        .onDisappear { model.leave() }
    }
}
