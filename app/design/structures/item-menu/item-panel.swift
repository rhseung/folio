import FolioDomain
import SwiftUI

// 항목 메뉴(`ItemMenu`)의 행을 팝오버나 시트 안의 목록으로 그린다. 같은 명령 표를 읽으므로 오른쪽 클릭 메뉴와 행이 같다.
struct ItemPanel<Source: ItemMenuSource>: View {
    let source: Source
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openLink) private var openLink
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    // 팝오버가 닫힌 뒤에 실행한다. 닫히는 중에 시트를 띄우면 iPhone에서 시트가 뜨지 않았다.
    @State private var pending: (@MainActor () -> Void)?

    var body: some View {
        let rows = source.commands.map(source.row)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                if i > 0 && rows[i - 1].group.band != row.group.band { Divider().padding(.leading, Theme.Space.l) }
                self.row(row)
            }
        }
        .onDisappear {
            pending?()
            pending = nil
        }
    }

    @ViewBuilder func row(_ row: MenuRow) -> some View {
        switch row.kind {
        case .action(let action), .open(_, _, let action):
            Button {
                run(action)
            } label: {
                line(row)
            }.buttonStyle(.pointing(.plain)).disabled(row.disabled)
        case .check(let on, let set):
            Button {
                run { set(!on) }
            } label: {
                line(row, checked: on)
            }.buttonStyle(.pointing(.plain)).disabled(row.disabled)
        case .submenu(let leaves):
            Menu {
                ForEach(leaves) { leaf in Button(leaf.title, systemImage: leaf.symbol) { run(leaf.action) } }
            } label: {
                line(row, more: true)
            }
            .menuButton(indicator: .hidden)
            .disabled(row.disabled)
        case .share(let link, let course):
            Menu {
                ForEach(LinkMenu.placements(multipleWindows: multipleWindows).filter { $0 != .here }, id: \.self) { placement in
                    Button(placement.title, systemImage: placement.symbol) { run { openLink(link, in: placement, course: course) } }
                }
                Divider()
                Button(.linkCopy, systemImage: "link") { copyLink(link) }
            } label: {
                line(row, more: true)
            }
            .menuButton(indicator: .hidden)
        }
    }

    func line(_ row: MenuRow, checked: Bool = false, more: Bool = false) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: row.symbol).frame(width: Theme.Size.smallIcon).accessibilityHidden(true)
                .foregroundStyle(row.role == .destructive ? Theme.Palette.danger : Theme.Palette.textSecondary)
            Text(row.title).foregroundStyle(row.role == .destructive ? Theme.Palette.danger : Theme.Palette.text).lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            if checked { Image(systemName: "checkmark").foregroundStyle(Theme.Palette.textSecondary).accessibilityHidden(true) }
            if more {
                Image(systemName: "chevron.right").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary).accessibilityHidden(
                    true)
            }
        }
        .font(Theme.Typeface.body)
        .padding(.horizontal, Theme.Space.l)
        .frame(minHeight: Theme.Size.rowHeight)
        .contentShape(.rect)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    func run(_ action: @escaping @MainActor () -> Void) {
        pending = action
        dismiss()
    }
}
