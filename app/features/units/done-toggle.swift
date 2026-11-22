import SwiftUI

// 다 함은 사용자가 직접 누르는 표시다. 준비 칩은 판정에서 앱이 계산하므로 둘을 따로 둔다(#575).
struct DoneToggle: View {
    let done: Bool
    let action: () -> Void

    var body: some View {
        Checkbox(isOn: done, action: action)
            .contentShape(TouchTarget())
            .help(Text(done ? .unitsDoneUndo : .unitsDone))
            .accessibilityLabel(Text(done ? .unitsDoneUndo : .unitsDone))
    }
}
