import SwiftUI

#if os(iOS)
import UIKit

// SwiftUI의 탭은 수정 키를 전하지 않고 `onModifierKeysChanged`는 Mac에서만 동작하므로, recognizer가 터치 이벤트에서
// 키를 읽어 둔다. 목록의 ⌘·⇧-누르기와 링크의 ⌘-누르기가 같은 값을 읽는다.
@MainActor enum TouchKeys {
    private(set) static var last: (flags: UIKeyModifierFlags, at: Date)?

    // 키를 읽은 뒤 1초가 지난 값은 그 누르기의 것이 아니다. 키보드 단축키가 연 링크가 오래전 터치의 키를 읽지 않게 한다.
    static var held: UIKeyModifierFlags? {
        guard let last, Date.now.timeIntervalSince(last.at) < 1 else { return nil }
        return last.flags
    }

    static func record(_ flags: UIKeyModifierFlags) { last = (flags, .now) }
}
#endif
