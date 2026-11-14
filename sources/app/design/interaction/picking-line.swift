import FolioDomain
import SwiftUI

struct PickingLine: View {
    let text: String
    let done: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(text).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: Theme.Space.s)
            Button(.commonDone, action: done).buttonStyle(.ghost)
        }
    }
}
