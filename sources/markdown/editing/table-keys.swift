import Foundation

extension TableCommand {
    public static let groups: [[TableCommand]] = [
        [.rowAbove, .rowBelow, .columnLeft, .columnRight],
        [.moveRowUp, .moveRowDown, .moveColumnLeft, .moveColumnRight],
        [.deleteRow, .deleteColumn],
        [.format],
    ]

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
