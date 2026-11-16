import FolioDomain
import SwiftUI

extension View {
    // 모든 칩이 같은 캡슐을 쓴다. `.small`은 보이기만 하는 칩(`Inset.tag`)이고, 그 밖은 누르는 칩(`Inset.control`)이다.
    // 바탕을 주지 않은 칩만 유리 위에서 옅은 바탕(`surface`)으로 바뀐다. 켜진 칩의 강조색까지 바꾸면 무엇을 골랐는지 사라진다.
    func chip(_ size: ControlSize = .regular, fill: Color? = nil) -> some View {
        modifier(ChipSurface(size: size, fill: fill))
    }
}

private struct ChipSurface: ViewModifier {
    let size: ControlSize
    let fill: Color?

    func body(content: Content) -> some View {
        let padded = content.padding(size == .small || size == .mini ? Theme.Inset.tag : Theme.Inset.control)
        Group {
            if let fill { padded.background(fill, in: .capsule) } else { padded.surface(Theme.Palette.fill, in: .capsule) }
        }
        .contentShape(.capsule)
    }
}
