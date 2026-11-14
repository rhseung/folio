import FolioDomain
import FolioMarkdown
import SwiftUI

struct InputGuideSheet: View {
    @State private var model: InputGuideModel
    @Environment(\.dismiss) private var dismiss

    static let width: CGFloat = 640
    static let height: CGFloat = 600

    init(workspace: Workspace, syntax: MathSyntax) {
        _model = State(initialValue: InputGuideModel(workspace: workspace, syntax: syntax))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.m) {
                    Text(.notesGuideTitle).font(Theme.Typeface.columnTitle)
                    Spacer(minLength: Theme.Space.s)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.ghostIcon)
                    .help(Text(.commonClose))
                    .accessibilityLabel(Text(.commonClose))
                    .keyboardShortcut(.cancelAction)
                }
                SearchField(prompt: String(localized: .notesGuideSearch), text: $model.search)
                ChipTabs(selection: $model.section, options: model.tabs)
            }
            .padding([.horizontal, .top], Theme.Space.xl)
            .padding(.bottom, Theme.Space.m)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    let shown = model.shown
                    ForEach(shown, id: \.section) { group in
                        Block(group.section.label) {
                            Card {
                                ForEach(Array(group.entries.enumerated()), id: \.element.id) { i, entry in
                                    CardRow(last: i == group.entries.count - 1) { InputGuideRow(entry: entry) }
                                }
                            }
                        }
                    }
                    if shown.isEmpty { EmptyLine(String(localized: .notesGuideNoMatch)) }
                }
                .padding([.horizontal, .bottom], Theme.Space.xl)
                .padding(.top, Theme.Space.s)
            }
            .overflowFade(.vertical)
        }
        #if os(macOS)
        .frame(width: Self.width, height: Self.height)
        #endif
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
    }
}
