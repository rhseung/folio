import FolioDomain
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 링크를 연 누르기에 실린 수정 키다. 화면마다 키를 읽지 않도록 `.here`로 여는 모든 링크가 여기서 여는 자리를 정한다.
@MainActor enum LinkClicks {
    // web view는 링크 누르기를 비동기로 넘겨서 그사이 다른 이벤트가 `currentEvent`가 된다. 그래서 누르기의 키를 직접 넘긴다.
    private static var handed: KeyCombo.Modifiers?

    static func with(_ modifiers: KeyCombo.Modifiers, _ body: () -> Void) {
        handed = modifiers
        defer { handed = nil }
        body()
    }

    static var current: LinkClick {
        if let handed { return LinkClick(handed) }
        #if os(macOS)
        // 키보드로 부른 메뉴 명령도 링크를 열므로, 누르기 이벤트에 실린 키만 본다.
        guard let event = NSApp.currentEvent else { return .here }
        switch event.type {
        case .leftMouseDown, .leftMouseUp: return LinkClick(KeyCombo.Modifiers(event.modifierFlags))
        case .otherMouseDown, .otherMouseUp: return event.buttonNumber == 2 ? .tabBehind : .here
        default: return .here
        }
        #else
        defer { touched = nil }
        guard let touched, Date.now.timeIntervalSince(touched.at) < 1 else { return .here }
        return LinkClick(touched.modifiers)
        #endif
    }

    #if os(iOS)
    // SwiftUI의 탭은 수정 키를 전하지 않으므로 창 전체에 붙인 recognizer가 터치 이벤트에서 키를 읽어 둔다.
    static var touched: (modifiers: KeyCombo.Modifiers, at: Date)?
    #endif
}
