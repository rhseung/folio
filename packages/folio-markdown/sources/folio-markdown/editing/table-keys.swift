import Foundation

/// A table command's key, always with ⌘. The edit views take it by key code on the Mac and as a key command on the iPad;
/// the input guide shows it.
public struct TableShortcut: Equatable, Sendable {
    public enum Key: Sendable { case up, down, left, right, enter, delete }

    public var key: Key
    public var shift = false
    public var option = false
    public var control = false

    public init(key: Key, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// As a menu writes it, the modifiers in the system's order: `⌃⌥⇧⌘↑`.
    public var symbols: String {
        let key = switch key {
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .enter: "↩"
        case .delete: "⌫"
        }
        return (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + "⌘" + key
    }
}

extension TableCommand {
    public static let groups: [[TableCommand]] = [
        [.rowAbove, .rowBelow, .columnLeft, .columnRight],
        [.moveRowUp, .moveRowDown, .moveColumnLeft, .moveColumnRight],
        [.deleteRow, .deleteColumn],
        [.format],
    ]

    /// Rows and columns are added with ⌘ and ⌥⌘, moved with ⌃⌘, deleted with ⇧⌘⌫ and ⌥⇧⌘⌫, as Typora and Obsidian's
    /// Advanced Tables have most of them. Tidying is rare enough for the menu alone.
    public var shortcut: TableShortcut? {
        switch self {
        case .rowBelow: TableShortcut(key: .enter)
        case .rowAbove: TableShortcut(key: .enter, shift: true)
        case .columnLeft: TableShortcut(key: .left, option: true)
        case .columnRight: TableShortcut(key: .right, option: true)
        case .moveRowUp: TableShortcut(key: .up, control: true)
        case .moveRowDown: TableShortcut(key: .down, control: true)
        case .moveColumnLeft: TableShortcut(key: .left, control: true)
        case .moveColumnRight: TableShortcut(key: .right, control: true)
        case .deleteRow: TableShortcut(key: .delete, shift: true)
        case .deleteColumn: TableShortcut(key: .delete, shift: true, option: true)
        case .format: nil
        }
    }

    public static func command(for shortcut: TableShortcut) -> TableCommand? {
        allCases.first { $0.shortcut == shortcut }
    }
}
