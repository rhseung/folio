import FolioDomain
import SwiftUI

struct LineIcon: View {
    let symbol: String
    var font: Font = Theme.Glyph.line
    var filled = false
    var duotone = false

    var body: some View {
        ZStack {
            if filled || duotone, Self.hasFill(symbol) {
                glyph(symbol + ".fill").opacity(filled ? Theme.Opacity.innerFill : Theme.Opacity.duotone)
            }
            glyph(symbol)
        }
    }

    // 없는 기호를 그리면 렌더할 때마다 경고가 기록되므로 먼저 확인한다.
    static func hasFill(_ symbol: String) -> Bool {
        #if os(macOS)
        NSImage(systemSymbolName: symbol + ".fill", accessibilityDescription: nil) != nil
        #else
        UIImage(systemName: symbol + ".fill") != nil
        #endif
    }

    func glyph(_ symbol: String) -> some View {
        // 기호마다 정사각형에 맞추지 않고 모든 기호에 같은 글꼴 크기를 쓴다. 맞추면 넓은 기호(학사모, 두 사람)가 줄어
        // 정사각형 기호 옆에서 획이 가늘어졌다. 고정 frame은 넓거나 높은 기호가 행의 글을 움직이지 않게 한다. 사이드바
        // 목록은 아이콘을 한 단계 키우므로(`imageScale(.large)`) scale도 고정한다. 그러지 않으면 사이드바 기호가 다른
        // 목록보다 한 크기 컸다. 굵기도 고정한다. 둘러싼 `.fontWeight`(고른 행의 semibold)는 글꼴 위에 더해져서, 위치
        // 표시와 고른 행의 기호가 사이드바보다 굵게 나왔다.
        Image(systemName: symbol)
            .font(font)
            .fontWeight(.regular)
            .imageScale(.medium)
            .frame(width: Theme.Size.tile, height: Theme.Size.tile)
    }
}
