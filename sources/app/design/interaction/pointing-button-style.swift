import FolioDomain
import SwiftUI

// 기본 스타일을 감싸므로 `.plain`이나 `.borderless`는 모양을 지킨다. 명시한 `.buttonStyle`은 이 스타일을 대체하므로,
// 루트에 한 번 두고 명시한 `.buttonStyle`마다 다시 감싼다.
struct PointingButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    let base: Base
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(base)
            #if os(macOS)
        .pointerStyle(isEnabled ? .link : nil)
            #endif
    }
}
