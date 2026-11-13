import FolioDomain
import FolioMarkdown
import SwiftUI

/// 입력 안내 (#395): the edit view's typing help on one sheet, by situation, each row what to type and what it gives.
/// Opened from 도움말 › 입력 안내 (⌘/), the `/` menu and the note bar.
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

/// One thing the editor does: its name and a short note, then the keys and what they give, `[[` → 대상 목록.
struct InputGuideRow: View {
    let entry: InputGuide.Entry

    static let nameWidth: CGFloat = 200

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(InputGuideModel.words(entry.title))
                    .font(Self.code(entry.title) ? Theme.Typeface.mono : Theme.Typeface.body)
                if let note = entry.note {
                    Text(InputGuideModel.words(note))
                        .font(Theme.Typeface.caption).monospaced(Self.code(note))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .frame(width: Self.nameWidth, alignment: .leading)
            FlowLayout(spacing: Theme.Space.xs, centered: true) {
                ForEach(Array(entry.steps.enumerated()), id: \.offset) { i, step in
                    switch step {
                    case .key(let key):
                        KeyCap(key)
                    case .result(let words):
                        HStack(spacing: Theme.Space.xs) {
                            if i > 0 { Text(verbatim: "→").foregroundStyle(Theme.Palette.textTertiary) }
                            Text(InputGuideModel.words(words)).monospaced(Self.code(words)).foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .font(Theme.Typeface.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    static func code(_ words: InputGuide.Words) -> Bool {
        if case .code = words { true } else { false }
    }
}

extension EnvironmentValues {
    /// Opens the input guide for a note of this math syntax; nil takes the syntax new notes get.
    @Entry var showInputGuide: @MainActor (MathSyntax?) -> Void = { _ in }
}

extension FocusedValues {
    /// The window's way to open the input guide, for 도움말 › 입력 안내 when no note is being written.
    @Entry var showInputGuide: (@MainActor (MathSyntax?) -> Void)?
}
