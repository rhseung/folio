import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

struct IntListField: View {
    @Binding var values: [Int]
    let unit: String
    let range: ClosedRange<Int>
    @State private var adding = false
    @State private var draft = 1

    var body: some View {
        FlowLayout(spacing: Theme.Space.tight, centered: true) {
            ForEach(values, id: \.self) { v in
                HStack(spacing: Theme.Space.xs) {
                    Text("\(v)\(unit)").monospacedDigit()
                    if values.count > 1 {
                        Button {
                            values.removeAll { $0 == v }
                        } label: {
                            Image(systemName: "xmark").font(Theme.Glyph.tiny).foregroundStyle(Theme.Palette.textTertiary)
                        }
                        .buttonStyle(.pointing(.plain))
                        .help(Text(.commonRemove))
                    }
                }
                .chip()
                .fixedSize()
                .contextMenu {
                    Button(.commonRemove, role: .destructive) { values.removeAll { $0 == v } }.disabled(values.count < 2)
                }
            }
            Button {
                draft = min((values.last ?? 0) + 1, range.upperBound)
                adding = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.ghost)
            .help(Text(.commonAdd))
            .popover(isPresented: $adding) {
                HStack(spacing: Theme.Space.s) {
                    ScrubField(
                        value: Binding(
                            get: { Double(draft) }, set: { draft = min(max(Int($0.rounded()), range.lowerBound), range.upperBound) }),
                        range: Double(range.lowerBound)...Double(range.upperBound), step: 1, width: 88)
                    Text(unit).foregroundStyle(Theme.Palette.textSecondary)
                    Button(.commonAdd, action: add).buttonStyle(.prominent)
                }
                .padding(Theme.Space.m)
            }
        }
    }

    func add() {
        values = Array(Set(values + [draft])).sorted()
        adding = false
    }
}
