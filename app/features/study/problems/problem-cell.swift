import FolioDomain
import SwiftUI

// 번호 칸 하나다. 색이 오답 상태를 말하고, 누르면 그 문제를 바로 푼다.
struct ProblemCell: View {
    let number: String
    let tone: Tone
    let help: String
    let solve: () -> Void

    var body: some View {
        Button(action: solve) {
            Text(verbatim: number).font(Theme.Typeface.bodyStrong).monospacedDigit().lineLimit(1)
                .foregroundStyle(tone == .plain ? Theme.Palette.textSecondary : tone.foreground)
                .padding(.horizontal, Theme.Space.s)
                .frame(minWidth: Theme.Size.solveCell, minHeight: Theme.Size.solveCell)
                .background(tone.fill, in: .rect(cornerRadius: Theme.Radius.control))
                .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .help(help)
        .accessibilityLabel(Text(verbatim: "\(number) \(help)"))
    }
}
