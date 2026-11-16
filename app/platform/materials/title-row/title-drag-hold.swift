#if os(macOS)
import AppKit
import SwiftUI

// 제목 줄 위에서 끄는 것(탭)에 포인터가 있는 동안 창 끌기를 멈춘다. 숨긴 제목 막대의 높이(창 위쪽 32pt) 안을 누르면 AppKit은 맞은
// view가 SwiftUI 탭이어도 창 hosting view의 `mouseDownCanMoveWindow`(true)를 보고 창을 끈다. 탭 capsule은 그 높이에 대부분 들어가
// 탭을 끌면 창이 움직였다. 창을 끌지는 누르는 순간에 정해지므로 누른 뒤에는 막을 수 없어, 포인터가 올라온 때 창의 `isMovable`을 끈다.
@MainActor final class TitleDragHold {
    weak var window: NSWindow? {
        didSet {
            if oldValue !== window { oldValue?.isMovable = true }
            apply()
        }
    }
    private var holders: Set<AnyHashable> = []

    var held: Bool { !holders.isEmpty }

    func hold(_ holder: AnyHashable, _ on: Bool) {
        if on { holders.insert(holder) } else { holders.remove(holder) }
        apply()
    }

    private func apply() {
        guard let window, window.isMovable == held else { return }
        window.isMovable = !held
    }
}

extension EnvironmentValues {
    @Entry var titleDragHold: TitleDragHold?
}

extension View {
    // 끄는 동안 포인터가 탭을 벗어나도 놓아 준다. 이미 시작한 SwiftUI 끌기는 창 끌기로 바뀌지 않는다.
    func holdsTitleDrag(_ holder: some Hashable) -> some View {
        modifier(TitleDragHolder(holder: AnyHashable(holder)))
    }
}

private struct TitleDragHolder: ViewModifier {
    let holder: AnyHashable
    @Environment(\.titleDragHold) private var hold

    func body(content: Content) -> some View {
        content
            .onHover { hold?.hold(holder, $0) }
            // 포인터 아래에서 탭이 닫히면 hover가 끝났다는 알림이 오지 않아 창이 끌리지 않는 채로 남는다.
            .onDisappear { hold?.hold(holder, false) }
    }
}
#endif
