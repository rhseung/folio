import FolioDomain
import SwiftUI

struct ExamDateTile: View {
    let date: Date?
    let tone: Tone

    var body: some View {
        VStack(spacing: 0) {
            Text(date?.formatted(.dateTime.month()) ?? "").font(Theme.Typeface.label)
            Text(date?.formatted(.dateTime.day()) ?? "-").font(Theme.Typeface.figureSmall)
        }
        .foregroundStyle(tone.foreground)
        .frame(width: Theme.Size.touchTarget, height: Theme.Size.touchTarget)
        .background(tone.fill, in: .rect(cornerRadius: Theme.Radius.control))
    }
}
