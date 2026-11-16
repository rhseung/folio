import Foundation

public struct KeyCombo: Hashable, Sendable {
    public enum Key: Hashable, Sendable {
        case character(Character)
        case tab, space, `return`, escape, delete
        case leftArrow, rightArrow, upArrow, downArrow
    }

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public var key: Key
    public var modifiers: Modifiers

    public init(_ key: Key, _ modifiers: Modifiers = .command) {
        self.key = key
        self.modifiers = modifiers
    }

    public init(_ character: Character, _ modifiers: Modifiers = .command) {
        self.init(.character(Character(character.lowercased())), modifiers)
    }
}
