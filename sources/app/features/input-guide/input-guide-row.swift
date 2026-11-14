import FolioDomain
import FolioMarkdown
import SwiftUI

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
