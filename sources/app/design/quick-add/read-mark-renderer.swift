import FolioDomain
import SwiftUI

struct ReadMarkRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            // 한글과 숫자는 다른 글꼴에서 오므로 한 구절이 run 여러 개에 걸친다. 이 run들을 알약 하나로 합친다.
            var pill: (rect: CGRect, mark: ReadMark)?
            func flush() {
                if let pill {
                    // 글리프보다 넓히지 않는다. 읽은 낱말과 다음 낱말 사이의 공백 하나가 자리의 전부라서, 그 안으로
                    // 들어간 알약이 이웃 낱말이나 다음 알약에 닿았다. 간격 자체를 넓히려면 필드의 글에 kerning을 줘야
                    // 하는데, 그러면 한글 조합 중에 글이 다시 쓰인다.
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.small).path(
                        in: pill.rect.insetBy(dx: 0, dy: -QuickAddLine.overhang))
                    context.fill(shape, with: .color(pill.mark.fill))
                }
                pill = nil
            }
            for run in line {
                if let mark = run[ReadMark.self] {
                    let rect = run.typographicBounds.rect
                    if let current = pill, current.mark == mark {
                        pill = (current.rect.union(rect), mark)
                    } else {
                        flush()
                        pill = (rect, mark)
                    }
                } else {
                    flush()
                }
            }
            flush()
        }
    }
}
