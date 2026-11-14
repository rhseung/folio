#if os(macOS)
import AppKit
import SwiftUI

// AppKit toolbar가 아니라 여기서 그린다. toolbar 스타일은 40pt(`unifiedCompact`)나 52pt(`unified`) 줄만 주고 그 사이는 없다. compact toolbar를
// 48pt로 늘리면 AppKit이 title bar를 다시 배치할 때마다 어긋났다(확대 버튼만 compact 줄의 가운데로 돌아갔다). 그래서 창은 title bar를 숨기고(`FolioApp`의
// `.hiddenTitleBar`) 이 줄이 내용의 맨 위가 된다. 높이와 배치는 Folio가 정하고, 빈 부분은 창을 끌며(`TitleDrag`), 창 버튼은 줄 가운데로 옮긴다(`TrafficLights`).
struct TitleRow<Leading: View, Trailing: View>: View {
    let lead: CGFloat
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, lead)
        .padding(.trailing, TitleRowEdges.trailing)
        .frame(height: Theme.Size.toolbarRow)
        .background { TitleDrag() }
    }
}
#endif
