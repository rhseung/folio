import FolioDomain
import SwiftUI

#if os(macOS)
import AppKit

// 노트 편집의 서식 키를 키 코드로 읽는다. 한국어 입력 소스에서는 ⌘와 함께 누른 글자가 바뀌기도 하기 때문이다.
@MainActor enum NoteFormatKeys {
    static let commands: [ShortcutID] = [.noteBold, .noteItalic]

    static func id(of event: NSEvent) -> ShortcutID? {
        let letters: [UInt16: Character] = [11: "b", 34: "i"]
        guard let letter = letters[event.keyCode] else { return nil }
        let combo = KeyCombo(letter, KeyCombo.Modifiers(event.modifierFlags))
        return commands.first { ShortcutTable.shortcut($0).bindings.contains { $0.combo == combo } }
    }
}
#endif
