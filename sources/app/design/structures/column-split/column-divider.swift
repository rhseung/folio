import FolioDomain
import SwiftUI

// safe area에서 멈추면 열 위쪽 옆의 경계선이 빠졌으므로, 띠 없는 툴바 아래까지 열 배경과 함께 올린다.
struct ColumnDivider: View {
    var body: some View { Theme.Palette.line.frame(width: 1).ignoresSafeArea() }
}
