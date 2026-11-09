import FolioMarkdown
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The table commands as the edit view offers them: their names in the app's language and symbols. Their keys and
/// groups are `TableCommand`'s, which the input guide reads too; what each one does to the source is `TableEditing`'s.
///
/// The keys act only with the caret in a table, so outside one they stay the text view's and the app's. None of them is
/// taken elsewhere in the note screen (⌘S, ⌘E, ⌘K, ⌘/, ⌘[ and ⌘] are).
@MainActor enum TableCommands {
    typealias Key = TableShortcut.Key
    typealias Shortcut = TableShortcut

    static let groups = TableCommand.groups

    static func title(_ command: TableCommand) -> String {
        switch command {
        case .rowAbove: String(localized: .notesTableRowAbove)
        case .rowBelow: String(localized: .notesTableRowBelow)
        case .columnLeft: String(localized: .notesTableColumnLeft)
        case .columnRight: String(localized: .notesTableColumnRight)
        case .deleteRow: String(localized: .notesTableDeleteRow)
        case .deleteColumn: String(localized: .notesTableDeleteColumn)
        case .moveRowUp: String(localized: .notesTableMoveRowUp)
        case .moveRowDown: String(localized: .notesTableMoveRowDown)
        case .moveColumnLeft: String(localized: .notesTableMoveColumnLeft)
        case .moveColumnRight: String(localized: .notesTableMoveColumnRight)
        case .format: String(localized: .notesTableFormat)
        }
    }

    static func symbol(_ command: TableCommand) -> String {
        switch command {
        case .rowAbove: "arrow.up.to.line"
        case .rowBelow: "arrow.down.to.line"
        case .columnLeft: "arrow.left.to.line"
        case .columnRight: "arrow.right.to.line"
        case .deleteRow, .deleteColumn: "trash"
        case .moveRowUp: "arrow.up"
        case .moveRowDown: "arrow.down"
        case .moveColumnLeft: "arrow.left"
        case .moveColumnRight: "arrow.right"
        case .format: "text.alignleft"
        }
    }

    static func shortcut(_ command: TableCommand) -> Shortcut? { command.shortcut }

    static func command(for shortcut: Shortcut) -> TableCommand? { TableCommand.command(for: shortcut) }

    #if os(macOS)
    /// Taken by key code, so the Korean input source doesn't change them.
    static func shortcut(of event: NSEvent) -> Shortcut? {
        let keys: [UInt16: Key] = [126: .up, 125: .down, 123: .left, 124: .right, 36: .enter, 76: .enter, 51: .delete]
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags.contains(.command), let key = keys[event.keyCode] else { return nil }
        return Shortcut(key: key, shift: flags.contains(.shift), option: flags.contains(.option), control: flags.contains(.control))
    }

    /// The table's commands as a submenu, each one off where it can't be done (a move past the edge, deleting the
    /// last row or column).
    static func menu(for table: TableSource, run: @escaping @MainActor (SourceEditing.Edit) -> Void) -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (i, group) in groups.enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            for command in group {
                let edit = table.edit(command)
                let item = LinkMenuItem(title(command), symbol: symbol(command)) { if let edit { run(edit) } }
                item.isEnabled = edit != nil
                if let shortcut = shortcut(command) {
                    item.keyEquivalent = equivalent(shortcut.key)
                    var mask: NSEvent.ModifierFlags = [.command]
                    if shortcut.shift { mask.insert(.shift) }
                    if shortcut.option { mask.insert(.option) }
                    if shortcut.control { mask.insert(.control) }
                    item.keyEquivalentModifierMask = mask
                }
                menu.addItem(item)
            }
        }
        let item = NSMenuItem(title: String(localized: .notesTableMenu), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)
        item.submenu = menu
        return item
    }

    static func equivalent(_ key: Key) -> String {
        let scalar: Int = switch key {
        case .up: NSUpArrowFunctionKey
        case .down: NSDownArrowFunctionKey
        case .left: NSLeftArrowFunctionKey
        case .right: NSRightArrowFunctionKey
        case .enter: 0x0D
        case .delete: 0x08
        }
        return String(Character(UnicodeScalar(scalar)!))
    }
    #else
    /// Hardware keyboard shortcuts on the iPad, the same keys as on the Mac. Its menu waits for the iPad's edit menu (#31).
    static func keyCommands(action: Selector) -> [UIKeyCommand] {
        TableCommand.allCases.compactMap { command in
            guard let shortcut = shortcut(command) else { return nil }
            let input = switch shortcut.key {
            case .up: UIKeyCommand.inputUpArrow
            case .down: UIKeyCommand.inputDownArrow
            case .left: UIKeyCommand.inputLeftArrow
            case .right: UIKeyCommand.inputRightArrow
            case .enter: "\r"
            case .delete: "\u{8}"
            }
            var flags: UIKeyModifierFlags = [.command]
            if shortcut.shift { flags.insert(.shift) }
            if shortcut.option { flags.insert(.alternate) }
            if shortcut.control { flags.insert(.control) }
            let key = UIKeyCommand(title: title(command), action: action, input: input, modifierFlags: flags, propertyList: command.rawValue)
            // Ahead of the text view's own keys, which ⌘ with the arrows would otherwise move the caret by.
            key.wantsPriorityOverSystemBehavior = true
            return key
        }
    }
    #endif
}
