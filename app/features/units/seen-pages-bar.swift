import SwiftUI

// 단원의 렉처 쪽마다 칸 하나다. 본 쪽은 과목 색, 아직 안 본 쪽은 옅게 깐다.
struct SeenPagesBar: View {
    @Environment(\.accent) private var accent
    let seen: [Bool]

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(Array(seen.enumerated()), id: \.offset) { _, on in
                RoundedRectangle(cornerRadius: Theme.Radius.small / 2).fill(on ? accent.color : accent.tint)
            }
        }
        // 좁은 칸에서는 막대가 줄어들어 행의 이름이 밀려나지 않게 한다.
        .frame(maxWidth: Theme.Size.seenPages.width).frame(height: Theme.Size.seenPages.height)
        .accessibilityHidden(true)
    }
}
