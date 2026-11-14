import Foundation

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

    public var symbols: String {
        let key =
            switch key {
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
