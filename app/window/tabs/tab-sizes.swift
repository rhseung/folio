import FolioDomain
import SwiftUI

// 더 보기 메뉴는 숨은 탭 수에 따라 폭이 바뀌므로 그려진 폭을 잰다. 잰 값은 `body`를 다시 그리지 않고 바로 줄에 알리도록
// state가 아니라 이 객체에 둔다.
@MainActor final class TabSizes {
    var more: CGFloat = 0
}
