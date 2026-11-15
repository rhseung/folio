import SwiftUI

// 열을 그리는 화면은 열린 열에 주어진 `closeColumn`을 보지 못하므로, 그 값을 읽도록 별도 뷰로 둔다.
struct ColumnPick<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    @Environment(\.closeColumn) private var closeColumn

    var body: some View {
        Button {
            action()
            closeColumn()
        } label: {
            label
        }
    }
}
