import FolioDomain
import SwiftUI

struct EntityRows<E: Entity, Header: View, Row: View>: View {
    @Binding var items: [E]
    let name: KeyPath<E, String>
    let make: () -> E
    @ViewBuilder let header: Header
    @ViewBuilder let row: (Binding<E>) -> Row
    @State private var removing: E?

    var body: some View {
        Card {
            HStack(spacing: Theme.Space.s) { header }
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, Theme.Space.m)
                .padding(.bottom, Theme.Space.xs)
            ForEach($items) { $item in
                CardRow {
                    HStack(spacing: Theme.Space.s) { row($item) }
                    Spacer(minLength: 0)
                    Button {
                        removing = item
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.pointing(.plain))
                    .help(Text(.commonDelete))
                }
                .contextMenu { Button(.commonDeleteEllipsis, role: .destructive) { removing = item } }
            }
            CardRow(last: true) {
                Button {
                    items.append(make())
                } label: {
                    Label(.commonAdd, systemImage: "plus").foregroundStyle(Theme.Palette.textSecondary)
                }
                .buttonStyle(.pointing(.plain))
            }
        }
        .confirmationDialog(
            Text(.entityRowsRemoveTitle(removing?[keyPath: name] ?? "")),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { item in
            Button(.commonDelete, role: .destructive) { items.removeAll { $0.id == item.id } }
        } message: { _ in
            Text(.entityRowsRemoveMessage)
        }
    }
}
