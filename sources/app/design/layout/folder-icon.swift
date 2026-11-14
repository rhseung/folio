import FolioDomain
import SwiftUI

// SF Symbols에는 열린 폴더가 없고 기호 하나를 다른 기호로 바꾸며 움직일 수 없으므로 직접 그린다. 닫힌 모양의 외곽선은
// `folder` 기호 디자인 템플릿(Regular-S)의 획 중심선을 사이드바가 그리는 medium 기호에 맞춘 것이다.
struct FolderIcon: View {
    var open: Bool
    var filled = false
    var duotone = false

    var body: some View {
        let t: CGFloat = open ? 1 : 0
        ZStack {
            FolderPart(kind: .fill, t: t).fill().opacity(filled ? Theme.Opacity.innerFill : duotone ? Theme.Opacity.duotone : 0)
            let line = StrokeStyle(lineWidth: FolderPart.stroke * Theme.Glyph.lineSize, lineCap: .round, lineJoin: .round)
            FolderPart(kind: .outline, t: t).stroke(style: line)
            FolderPart(kind: .corners, t: t).stroke(style: line).opacity(open ? 1 : 0)
        }
        .frame(width: Theme.Size.tile, height: Theme.Size.tile)
        .animation(Theme.Motion.standard, value: open)
        .accessibilityHidden(true)
    }
}
