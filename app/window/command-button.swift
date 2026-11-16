import FolioDomain
import SwiftUI

// 메뉴 막대 명령이다. 이름과 키를 모두 단축키 등록표에서 읽는다.
struct CommandButton: View {
    let id: ShortcutID
    var key: KeyCombo?
    let action: () -> Void

    init(_ id: ShortcutID, key: KeyCombo? = nil, action: @escaping () -> Void) {
        self.id = id
        self.key = key
        self.action = action
    }

    var body: some View {
        let shortcut = ShortcutTable.shortcut(id)
        Button(shortcut.name, action: action).keyboardShortcut((key ?? shortcut.key)?.keyboardShortcut)
    }
}
