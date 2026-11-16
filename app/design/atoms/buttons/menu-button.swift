import SwiftUI

extension View {
    // `.button` 메뉴에 Folio의 button style을 주면 pop-up 버튼으로 돌아가므로, 메뉴는 시스템 스타일로 그리고 손가락 포인터만 더한다.
    // 기본은 plain이라 라벨의 글꼴과 색을 그대로 둔다. `tinted`는 borderless라 라벨을 강조색으로 칠한다. borderless는 라벨 이미지를
    // 컨트롤의 크기와 색으로 다시 그리므로, 라벨을 직접 그린 메뉴(상태 아이콘, 칩)는 plain으로 둔다.
    @ViewBuilder func menuButton(tinted: Bool = false, indicator: Visibility = .automatic) -> some View {
        let menu = menuStyle(.button).menuIndicator(indicator)
        if tinted { menu.buttonStyle(.borderless).pointingHand() } else { menu.buttonStyle(.plain).pointingHand() }
    }
}
