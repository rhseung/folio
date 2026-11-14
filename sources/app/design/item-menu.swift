import FolioDomain
import SwiftUI

struct MenuRow: Identifiable {
    // iPad에서는 하위 메뉴가 그 메뉴를 연 메뉴를 대체하고, 두 단계가 되면 돌아갈 길이 없어진다. 그래서 하위 메뉴 행은
    // 일반 동작만 받아 메뉴가 한 단계까지만 깊어진다.
    struct Leaf: Identifiable {
        let id: AnyHashable
        let title: String
        let symbol: String
        var checked: Bool? = nil
        let action: @MainActor () -> Void
    }

    enum Kind {
        case action(@MainActor () -> Void)
        case check(Bool, @MainActor (Bool) -> Void)
        case submenu([Leaf])
        case share(AppLink, course: UUID?)
    }

    let id: AnyHashable
    let group: MenuGroup
    let title: String
    let symbol: String
    var role: ButtonRole?
    var disabled = false
    let kind: Kind

    init(id: AnyHashable, group: MenuGroup, title: String, symbol: String, role: ButtonRole? = nil, disabled: Bool = false, kind: Kind) {
        self.id = id
        self.group = group
        self.title = title
        self.symbol = symbol
        self.role = role
        self.disabled = disabled
        self.kind = kind
    }

    init<C: ItemCommand>(
        _ command: C, _ title: LocalizedStringResource, _ symbol: String, role: ButtonRole? = nil, disabled: Bool = false, _ kind: Kind
    ) {
        self.init(
            id: command, group: command.group, title: String(localized: title), symbol: symbol, role: role, disabled: disabled, kind: kind)
    }

    static func remove<C: ItemCommand>(_ command: C, _ action: @escaping @MainActor () -> Void) -> MenuRow {
        MenuRow(command, .commonDeleteEllipsis, "trash", role: .destructive, .action(action))
    }

    static func edit<C: ItemCommand>(_ command: C, _ action: @escaping @MainActor () -> Void) -> MenuRow {
        MenuRow(command, .commonEditEllipsis, "pencil", .action(action))
    }

    static func open<C: ItemCommand>(_ command: C, _ action: @escaping @MainActor () -> Void) -> MenuRow {
        MenuRow(command, .commonOpen, "arrow.right.circle", .action(action))
    }

    static func share<C: ItemCommand>(_ command: C, _ link: AppLink, course: UUID?) -> MenuRow {
        MenuRow(command, .menuShare, "square.and.arrow.up", .share(link, course: course))
    }

    static func showInFinder<C: ItemCommand>(_ command: C, _ url: URL) -> MenuRow {
        MenuRow(command, .commonShowInFinder, "folder", .action { revealInFinder(url) })
    }
}

@MainActor func revealInFinder(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.activateFileViewerSelecting([url])
    #endif
}

@MainActor protocol ItemMenuSource {
    associatedtype Command: ItemCommand
    var commands: [Command] { get }
    func row(_ command: Command) -> MenuRow
}

struct ItemMenu<Source: ItemMenuSource>: View {
    let source: Source

    var body: some View {
        let rows = source.commands.map(source.row)
        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
            if i > 0 && rows[i - 1].group.band != row.group.band { Divider() }
            MenuRowView(row: row)
        }
    }
}

struct ItemButton<Source: ItemMenuSource>: View {
    let source: Source
    let command: Source.Command

    var body: some View {
        if source.commands.contains(command) {
            let row = source.row(command)
            switch row.kind {
            case .action(let action):
                Button(row.title, systemImage: row.symbol, role: row.role) { action() }.disabled(row.disabled)
            case .check(let on, let set):
                Button(row.title) { set(!on) }.disabled(row.disabled)
            case .submenu, .share:
                EmptyView()
            }
        }
    }
}

struct MenuRowView: View {
    let row: MenuRow

    var body: some View {
        switch row.kind {
        case .action(let action):
            Button(row.title, systemImage: row.symbol, role: row.role) { action() }.disabled(row.disabled)
        case .check(let on, let set):
            Toggle(isOn: Binding(get: { on }, set: { set($0) })) { Label(row.title, systemImage: row.symbol) }
                .disabled(row.disabled)
        case .submenu(let leaves):
            Menu {
                ForEach(leaves) { leaf in
                    if let checked = leaf.checked {
                        // iPad 메뉴도 Mac처럼 체크 표시를 그리도록 `Toggle`로 둔다.
                        Toggle(isOn: Binding(get: { checked }, set: { _ in leaf.action() })) { Label(leaf.title, systemImage: leaf.symbol) }
                    } else {
                        Button(leaf.title, systemImage: leaf.symbol) { leaf.action() }
                    }
                }
            } label: {
                Label(row.title, systemImage: row.symbol)
            }
            .disabled(row.disabled)
        case .share(let link, let course):
            ShareMenu(link: link, course: course)
        }
    }
}

struct ShareMenu: View {
    let link: AppLink
    var course: UUID?
    @Environment(\.openLink) private var openLink
    @Environment(\.supportsMultipleWindows) private var multipleWindows

    var body: some View {
        Menu {
            ForEach(LinkMenu.placements(multipleWindows: multipleWindows).filter { $0 != .here }, id: \.self) { placement in
                Button(placement.title, systemImage: placement.symbol) { openLink(link, in: placement, course: course) }
            }
            Divider()
            Button(.linkCopy, systemImage: "link") { copyLink(link) }
        } label: {
            Label(.menuShare, systemImage: "square.and.arrow.up")
        }
    }
}

struct PageMenuButton<Items: View>: View {
    var inBar = false
    @ViewBuilder var items: Items

    var body: some View {
        if inBar {
            Menu {
                items
            } label: {
                Label(.menuMore, systemImage: "ellipsis")
            }
            .help(Text(.menuMore))
        } else {
            Menu {
                items
            } label: {
                Label(.menuMore, systemImage: "ellipsis").labelStyle(.iconOnly)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: Theme.Size.toolbarButton, height: Theme.Size.toolbarButton)
                    .contentShape(TouchTarget())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless).pointingHand()
            .fixedSize()
            .help(Text(.menuMore))
        }
    }
}
