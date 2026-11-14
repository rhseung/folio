#if os(macOS)
import AppKit
import SwiftUI

// AppKit은 title bar가 바뀔 때마다(창이 key가 될 때, 탭마다 제목이 바뀔 때, 크기를 바꿀 때, 전체 화면에서 나올 때) 버튼을 title bar의 가운데로 다시 배치한다. 닫기, 최소화, 확대
// 순으로 옮기는데, 그 단계가 도는 중에 되돌려 놓은 버튼은 이미 제자리로 읽혀 마지막 버튼(확대)이 남겨졌다. 그래서 그 단계가 끝난 뒤에만 버튼을 둔다. AppKit의 frame 변경과 창의 변경마다 run
// loop의 다음 차례, 창을 그리기 전에 한 번 두도록 요청한다. 목표가 창 좌표이므로 다시 두어도 바뀌는 것이 없다. 공개 API(`standardWindowButton`과 frame)만 쓴다. 전체 화면에서는
// 버튼이 메뉴 막대 쪽의 다른 창에 있으므로 건드리지 않는다.
struct TrafficLights: NSViewRepresentable {
    let center: CGFloat
    let fullScreen: (Bool) -> Void

    func makeNSView(context: Context) -> Probe { Probe(center: center, fullScreen: fullScreen) }
    func updateNSView(_ view: Probe, context: Context) {
        view.center = center
        view.fullScreen = fullScreen
        view.place()
    }

    final class Probe: NSView {
        var center: CGFloat
        var fullScreen: (Bool) -> Void
        private var windowObservers: [NSObjectProtocol] = []
        private var frameObservers: [NSObjectProtocol] = []
        private var watched: [ObjectIdentifier] = []
        private var spacing: [CGFloat] = []

        init(center: CGFloat, fullScreen: @escaping (Bool) -> Void) {
            self.center = center
            self.fullScreen = fullScreen
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for observer in windowObservers + frameObservers { NotificationCenter.default.removeObserver(observer) }
            windowObservers = []
            frameObservers = []
            watched = []
            guard let window else { return }

            let center = NotificationCenter.default
            let changes: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
                NSWindow.didExitFullScreenNotification, NSWindow.didChangeBackingPropertiesNotification,
                NSWindow.didChangeScreenNotification, NSWindow.didDeminiaturizeNotification,
            ]
            windowObservers = changes.map { name in
                center.addObserver(forName: name, object: window, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { self?.placeNowAndNextTurn() }
                }
            }
            let going: [(Notification.Name, Bool)] = [
                (NSWindow.willEnterFullScreenNotification, true), (NSWindow.willExitFullScreenNotification, false),
            ]
            windowObservers += going.map { name, full in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.fullScreen(full) }
                }
            }

            let full = window.styleMask.contains(.fullScreen)
            Task { @MainActor [weak self] in self?.fullScreen(full) }
            placeNowAndNextTurn()
        }

        static let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        private var placingNextTurn = false

        private func placeNowAndNextTurn() {
            place()
            placeNextTurn()
        }

        private func placeNextTurn() {
            guard !placingNextTurn else { return }
            placingNextTurn = true
            Task { @MainActor [weak self] in
                self?.placingNextTurn = false
                self?.place()
            }
        }

        func place() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            let buttons = Self.kinds.compactMap { window.standardWindowButton($0) }.filter { $0.window === window }
            watch(buttons)
            for (button, offset) in zip(buttons, spacing) {
                guard let host = button.superview else { continue }
                let inWindow = host.convert(button.frame, to: nil)
                var target = inWindow
                target.origin.x = center + offset - inWindow.width / 2
                target.origin.y = window.frame.height - center - inWindow.height / 2
                let frame = host.convert(target, from: nil)
                let origin = host.backingAlignedRect(frame, options: .alignAllEdgesNearest).origin
                if abs(button.frame.origin.x - origin.x) > 0.25 || abs(button.frame.origin.y - origin.y) > 0.25 {
                    button.setFrameOrigin(origin)
                }
            }
        }

        private func watch(_ buttons: [NSButton]) {
            let ids = buttons.map(ObjectIdentifier.init)
            guard ids != watched else { return }
            for observer in frameObservers { NotificationCenter.default.removeObserver(observer) }
            watched = ids
            // 아직 옮기지 않은 버튼에서 한 번만 읽는다. 둘 때마다 읽으면 다른 버튼은 옮겨진 채 AppKit이 방금 되돌린 버튼 하나의 간격이 그대로 간격 값에 들어갔다.
            let middles = buttons.map { $0.convert($0.bounds, to: nil).midX }
            spacing = middles.map { $0 - (middles.first ?? 0) }
            frameObservers = buttons.map { button in
                button.postsFrameChangedNotifications = true
                return NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: button, queue: nil) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.placeNextTurn() }
                }
            }
        }
    }
}
#endif
