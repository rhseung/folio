#if os(macOS)
import AppKit
import SwiftUI

extension View {
    func mainWindowFrame(firstRun: Bool) -> some View { modifier(MainWindowFrame(firstRun: firstRun)) }
}

private struct MainWindowFrame: ViewModifier {
    let firstRun: Bool
    @State private var host = WindowHost()
    @State private var before: NSRect?
    // 시스템 타이틀 바의 높이다. 첫 실행은 그 아래까지 그리지만 창은 그것을 내용 밖으로 세므로, 내용은 시안의 창보다
    // 이만큼 짧다.
    @State private var titleBar: CGFloat = 0

    func body(content: Content) -> some View {
        let small = CGSize(width: Theme.Size.firstRunWindow.width, height: Theme.Size.firstRunWindow.height - titleBar)
        let least = Theme.Size.windowMin
        // 두 갈래가 아니라 bounds만 바뀌는 frame 하나로 둔다. 갈래를 두면 root view를 다시 만들어 탭을 잃는다. 양쪽으로
        // 제한해 창의 최소 크기가 이 frame의 것이 되게 한다. 최소 크기만 두면 hosting view가 크기 조절이나 끌기의
        // 배치마다 창 전체의 내용을 쟀다.
        content
            .frame(
                minWidth: firstRun ? small.width : least.width, maxWidth: firstRun ? small.width : .infinity,
                minHeight: firstRun ? small.height : least.height, maxHeight: firstRun ? small.height : .infinity
            )
            .background(
                WindowReader { window in
                    host.window = window
                    titleBar = window.frame.height - window.contentLayoutRect.height
                    fit(window, animate: false)
                }
            )
            .onChange(of: firstRun) {
                guard let window = host.window else { return }
                fit(window, animate: true)
            }
    }

    private func fit(_ window: NSWindow, animate: Bool) {
        // SwiftUI가 새 bounds를 창에 적용한 뒤에 해야 한다. 그러지 않으면 창이 이전 bounds를 유지한다.
        DispatchQueue.main.async {
            guard !window.styleMask.contains(.fullScreen), let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let frame: NSRect
            let small = Theme.Size.firstRunWindow
            if firstRun {
                guard window.frame.size != small else { return }
                before = window.frame
                frame = centered(small, in: visible)
            } else {
                guard window.frame.size == small else { return }
                frame =
                    before
                    ?? centered(
                        window.frameRect(forContentRect: NSRect(origin: .zero, size: WindowSize.opening(in: visible.size))).size,
                        in: visible)
                before = nil
            }
            window.setFrame(frame, display: true, animate: animate)
        }
    }

    private func centered(_ size: CGSize, in visible: NSRect) -> NSRect {
        NSRect(
            x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
            width: size.width, height: size.height)
    }
}
#endif
