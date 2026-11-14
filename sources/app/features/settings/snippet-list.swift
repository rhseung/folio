import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

struct SnippetList: View {
    @Binding var snippets: [MathSnippet]
    var defaults = MathSnippet.defaults
    var placed = true

    var body: some View {
        Card {
            ForEach(snippets.indices, id: \.self) { i in
                CardRow {
                    TextField(String(localized: .settingsSnippetTrigger), text: field(i, \.trigger))
                        .font(Theme.Typeface.mono)
                        .pill(width: 72, alignment: .leading)
                    TextField(String(localized: .settingsSnippetBody), text: field(i, \.body), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.Typeface.mono)
                    if placed {
                        ChoiceMenu(
                            selection: field(i, \.inMath),
                            options: [
                                (false, String(localized: .settingsSnippetInText)),
                                (true, String(localized: .settingsSnippetInMath)),
                            ])
                    }
                    Button {
                        snippets.remove(at: i)
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.pointing(.plain))
                    .help(Text(.commonDelete))
                }
                .contextMenu { Button(.commonDelete, role: .destructive) { if snippets.indices.contains(i) { snippets.remove(at: i) } } }
            }
            CardRow(last: true) {
                Button {
                    snippets.append(MathSnippet(trigger: "", body: "", inMath: true))
                } label: {
                    Label(.settingsSnippetAdd, systemImage: "plus").foregroundStyle(Theme.Palette.textSecondary)
                }
                .buttonStyle(.pointing(.plain))
                Spacer()
                Button(.settingsSnippetReset) { snippets = defaults }
                    .buttonStyle(.ghost)
                    .disabled(snippets == defaults)
            }
        }
    }

    // 목록을 다시 그리는 동안 지운 행에 값을 한 번 더 물을 수 있으므로 인덱스를 확인한다.
    func field<T>(_ i: Int, _ key: WritableKeyPath<MathSnippet, T>) -> Binding<T> {
        Binding(
            get: {
                snippets.indices.contains(i) ? snippets[i][keyPath: key] : MathSnippet(trigger: "", body: "", inMath: true)[keyPath: key]
            },
            set: { if snippets.indices.contains(i) { snippets[i][keyPath: key] = $0 } })
    }
}
