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
