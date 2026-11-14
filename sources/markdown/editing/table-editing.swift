import Foundation
import Markdown

public enum TableEditing {
    public static func table(in text: NSString, selection: NSRange) -> TableSource? {
        TableSource(text, selection)
    }

    public static func edit(_ command: TableCommand, in text: NSString, selection: NSRange) -> SourceEditing.Edit? {
        table(in: text, selection: selection)?.edit(command)
    }
}
