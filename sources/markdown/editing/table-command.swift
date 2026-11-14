import Foundation
import Markdown

public enum TableCommand: String, CaseIterable, Sendable {
    case rowAbove, rowBelow, columnLeft, columnRight
    case deleteRow, deleteColumn
    case moveRowUp, moveRowDown, moveColumnLeft, moveColumnRight
    case format
}
