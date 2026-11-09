import SwiftUI

/// The note's headings, indented by level, the one being read marked. Tapping one goes there; beside a folded heading a
/// chevron opens the deeper ones under it. The same list stands beside the note and in the bar button's popover.
struct NoteOutlineList: View {
    let model: NoteOutlineModel
    /// After a jump: the popover closes, the column stays.
    var picked: () -> Void = {}
    @Environment(\.accent) private var accent

    var body: some View {
        let rows = model.rows
        let marked = rows.first(where: \.marked)?.id
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Caption(String(localized: .notesOutlineTitle))
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, Theme.Space.m)
                .padding(.bottom, Theme.Space.xxs)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row($0).id($0.id) }
                    }
                    .padding(.horizontal, Theme.Space.s)
                    .padding(.bottom, Theme.Space.m)
                }
                .overflowFade(.vertical)
                .onChange(of: marked) { _, id in
                    if let id { withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(id) } }
                }
                .onAppear { if let marked { proxy.scrollTo(marked, anchor: .center) } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func row(_ row: NoteOutlineModel.Row) -> some View {
        HStack(spacing: 0) {
            Button {
                model.jump(row.index)
                picked()
            } label: {
                Text(row.title)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fontWeight(row.marked ? .semibold : .regular)
                    .foregroundStyle(row.marked ? Theme.Palette.text : Theme.Palette.textSecondary)
                    .padding(.leading, CGFloat(row.indent) * Theme.Space.m)
                    .padding(Theme.Inset.listRow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .help(row.title)
            if row.folds {
                Button { withAnimation(.snappy(duration: 0.25)) { model.toggle(row.index) } } label: {
                    Image(systemName: "chevron.right")
                        .font(Theme.Typeface.caption)
                        .rotationEffect(.degrees(row.open ? 90 : 0))
                }
                .buttonStyle(.ghostIcon)
                .help(Text(row.open ? .commonCollapse : .commonExpand))
                .accessibilityLabel(Text(row.open ? .commonCollapse : .commonExpand))
            }
        }
        .font(Theme.Typeface.body)
        .background(row.marked ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
    }
}
