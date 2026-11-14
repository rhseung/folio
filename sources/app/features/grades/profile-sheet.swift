import FolioDomain
import SwiftUI

struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(.requirementsProfile).font(Theme.Typeface.columnTitle)
            ProfileCard(workspace: workspace)
            Text(.profileNote).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                .padding(.horizontal, Theme.Space.m)
            HStack {
                Spacer()
                Button(.commonClose) { dismiss() }.buttonStyle(.prominent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 520)
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
        .controlSize(.large)
    }
}
