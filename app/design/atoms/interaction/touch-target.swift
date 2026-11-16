import FolioDomain
import SwiftUI

// 터치에서만 넓힌다. 포인터는 더 정밀하게 가리키고, Mac에서 넓은 영역은 옆 뷰를 노린 클릭을 가져갔다.
struct TouchTarget: Shape {
    var side: CGFloat = Theme.Size.touchTarget

    func path(in rect: CGRect) -> Path {
        #if os(macOS)
        Path(rect)
        #else
        Path(rect.insetBy(dx: min(0, (rect.width - side) / 2), dy: min(0, (rect.height - side) / 2)))
        #endif
    }
}
