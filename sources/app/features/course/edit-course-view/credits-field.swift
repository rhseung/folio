import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct CreditsField: View {
    @Binding var credits: Double?

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            TextField("3", value: $credits, format: .number).pill(width: 56).multilineTextAlignment(.trailing)
            Text(.courseEditCredits).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
