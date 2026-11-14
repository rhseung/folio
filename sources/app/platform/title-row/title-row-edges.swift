import SwiftUI

#if os(macOS)
import AppKit

enum TitleRowEdges {
    // 닫기 버튼의 중심은 창 왼쪽 가장자리에서도 위쪽 가장자리에서도 같은 거리(줄의 가운데)에 둔다. title bar가 없는 창에서 AppKit은 버튼을 옆에서 16pt에 두는데, 위쪽보다 옆에 가까워
    // 한쪽으로 쏠려 보였고 사이드바 아이콘보다 왼쪽에 섰다. 나머지 두 버튼은 AppKit의 간격을 따른다.
    static let lights = Theme.Size.toolbarRow / 2

    static func lead(fullScreen: Bool) -> CGFloat { fullScreen ? trailing : 92 }

    static let trailing = (Theme.Size.toolbarRow - Theme.Size.toolbarButton) / 2
}
#else
enum TitleRowEdges {
    static func lead(fullScreen: Bool) -> CGFloat { Theme.Space.l }
    static let trailing = Theme.Space.l
}
#endif
