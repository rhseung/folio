import Foundation

/// The one order of every item menu (#403). A command's group places it, so no screen orders rows by hand and the same
/// kind of row sits in the same place in every menu.
public enum MenuGroup: Int, CaseIterable, Comparable, Sendable {
    case open, start, state, edit, arrange, share, remove

    public static func < (a: MenuGroup, b: MenuGroup) -> Bool { a.rawValue < b.rawValue }

    /// Dividers fall between bands rather than between every group: what is done with the item now, what keeps it,
    /// and removing it alone at the end. A divider per group cut a seven-row menu into five pieces (2026-11-09 mockup).
    public var band: Int {
        switch self {
        case .open, .start, .state: 0
        case .edit, .arrange, .share: 1
        case .remove: 2
        }
    }
}

/// One thing a menu row does to an item. Each kind declares its own commands, and what the data allows decides which
/// of them an item's menu holds.
public protocol ItemCommand: Hashable, Sendable {
    var group: MenuGroup { get }
}

/// Where a menu is shown, for the only rows that change with it: "열기" is left out on the item's own screen, and a
/// screen that holds the item through a link adds the row that lets go of it.
public enum MenuHost: Hashable, Sendable {
    /// Any screen other than the item's own: Today, the ribbon, the course overview, search.
    case elsewhere
    /// The item's own screen, where it is already open.
    case own
    /// A unit's page, which lists the item as linked to that unit.
    case unit(UUID)
    /// An exam's card, which lists the item as linked to that exam.
    case exam(UUID)
    /// The list that keeps the items in an order of their own (the sidebar's courses, a course's units): opening one
    /// is still a step, and moving it up and down is offered.
    case list

    /// Everywhere but the item's own screen the menu leads with "열기".
    public var opensItem: Bool { self != .own }

    /// Only where the items are listed in the order the user sets: moving one from anywhere else moves it out of sight.
    public var orders: Bool { self == .list }
}

extension Array where Element: ItemCommand {
    /// By group, keeping the declared order within a group.
    public func inMenuOrder() -> [Element] {
        enumerated().sorted { ($0.element.group, $0.offset) < ($1.element.group, $1.offset) }.map(\.element)
    }
}
