import FolioDomain
import SwiftUI

// 풀기와 모의시험의 화면이다. 시트가 아니라 창 안의 화면이라서, 문제지 쪽은 옆 칸에 열고 넓히거나 접을 수 있다.
struct SolveScreen: View {
    @State private var model: SolveModel

    init(workspace: Workspace, request: SolveRequest) {
        _model = State(initialValue: SolveSessions.model(workspace: workspace, request: request))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .setup:
                ScrollView { SolveSetup(model: model).frame(maxWidth: .infinity) }.scrollBounceBehavior(.basedOnSize)
            case .solving:
                if let sheet = model.sheet {
                    SolveSheet(model: sheet, onClose: { model.close($0, $1) })
                } else {
                    SolveRun(model: model)
                }
            case .done: SolveResult(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Palette.page)
        .courseAccent(model.accent)
        .onDisappear { model.leave() }
    }
}

// 화면을 떠났다가 기록으로 돌아오면 같은 풀기의 답과 판정을 다시 보인다. iPhone처럼 문제지 쪽을 같은 칸에 열면 화면이
// 사라지므로, 모델을 뷰가 아니라 풀기 ID로 붙잡아 둔다. 오래된 풀기부터 버려 몇 개만 남긴다.
@MainActor
private enum SolveSessions {
    static let kept = 8
    struct Key: Hashable {
        var workspace: ObjectIdentifier
        var run: UUID
    }

    static var models: [(key: Key, model: SolveModel)] = []

    static func model(workspace: Workspace, request: SolveRequest) -> SolveModel {
        let key = Key(workspace: ObjectIdentifier(workspace), run: request.id)
        if let i = models.firstIndex(where: { $0.key == key }) {
            let found = models.remove(at: i)
            models.append(found)
            return found.model
        }
        let model = SolveModel(workspace: workspace, request: request)
        models.append((key, model))
        if models.count > kept { models.removeFirst(models.count - kept) }
        return model
    }
}
