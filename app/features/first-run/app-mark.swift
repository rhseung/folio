import SwiftUI

// iPad에는 앱 아이콘을 읽는 API가 없고 `.icon` 파일은 빌드할 때에야 아이콘이 되므로, 아이콘을 읽지 않고 직접 그린다.
struct AppMark: View {
    var side: CGFloat = Theme.Size.appMark

    var body: some View {
        // 아이콘 격자는 폭 1024다. 막대는 높이 168, 간격 52이고, 176에서 시작하며 길이는 664, 488, 312다.
        let unit = side / 1024
        VStack(alignment: .leading, spacing: 52 * unit) {  // design: one-off, the icon's own proportions
            bar(664 * unit, Theme.Palette.markInk)
            bar(488 * unit, Theme.Palette.markCoral)
            bar(312 * unit, Theme.Palette.markCoral)
        }
        .padding(.leading, 176 * unit)  // design: one-off, the icon's own proportions
        .frame(width: side, height: side, alignment: .leading)
        // 시스템 아이콘의 모서리는 한 변의 약 22%를 반지름으로 하는 continuous 둥근 사각형이다.
        .background(Theme.Palette.markBack, in: .rect(cornerRadius: side * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous).strokeBorder(Theme.Palette.lineSoft))
        .accessibilityHidden(true)
    }

    private func bar(_ length: CGFloat, _ color: Color) -> some View {
        Capsule().fill(color).frame(width: length, height: 168 * side / 1024)
    }
}
