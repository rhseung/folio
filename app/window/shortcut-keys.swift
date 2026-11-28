import FolioDomain
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension KeyCombo {
    var keyboardShortcut: KeyboardShortcut { KeyboardShortcut(equivalent, modifiers: eventModifiers) }

    var equivalent: KeyEquivalent {
        switch key {
        case .character(let c): KeyEquivalent(c)
        case .tab: .tab
        case .space: .space
        case .return: .return
        case .escape: .escape
        case .delete: .delete
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        }
    }

    var eventModifiers: EventModifiers {
        var m: EventModifiers = []
        if modifiers.contains(.command) { m.insert(.command) }
        if modifiers.contains(.shift) { m.insert(.shift) }
        if modifiers.contains(.option) { m.insert(.option) }
        if modifiers.contains(.control) { m.insert(.control) }
        return m
    }
}

extension View {
    // 키는 화면에 적지 않고 등록표에서 읽는다. 같은 단추가 여럿 보이는 화면은 지금 답할 것에만 키를 주고 나머지에는 nil을 준다.
    func shortcut(_ id: ShortcutID?) -> some View {
        keyboardShortcut(id.flatMap { ShortcutTable.shortcut($0).key?.keyboardShortcut })
    }

    // 키가 여럿인 명령에서 `index`번째 키다. 보기 고르기처럼 키의 차례가 대상의 차례인 명령에 쓴다.
    func shortcut(_ id: ShortcutID, at index: Int) -> some View {
        let bindings = ShortcutTable.shortcut(id).bindings
        return keyboardShortcut(bindings.indices.contains(index) ? bindings[index].combo.keyboardShortcut : nil)
    }
}

extension KeyCombo.Modifiers {
    #if os(macOS)
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
    #else
    init(_ flags: UIKeyModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.alternate) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
    #endif
}

#if os(macOS)
extension KeyCombo {
    // 화살표만 받는다. 글자 키는 입력 소스에 따라 문자가 바뀌어 메뉴의 키와 같은 길로 받는다.
    init?(_ event: NSEvent) {
        let arrows: [UInt16: Key] = [123: .leftArrow, 124: .rightArrow, 125: .downArrow, 126: .upArrow]
        guard let key = arrows[event.keyCode] else { return nil }
        self.init(key, Modifiers(event.modifierFlags))
    }
}
#endif
