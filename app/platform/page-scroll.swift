import SwiftUI

extension View {
    // SwiftUI는 내용이 화면에 들어갈 때만 바운스를 멈출 수 있다(`scrollBounceBehavior(.basedOnSize)`). 창보다 긴 페이지는 위아래로 늘어나서 배경이 패널 가장자리에서
    // 떨어졌다. 그래서 이 내용을 감싼 플랫폼 scroll view가 아예 바운스하지 않게 한다.
    func pageScrollWithoutBounce() -> some View { background { NoBounce() } }
}

#if os(macOS)
private struct NoBounce: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}

    final class Probe: NSView {
        private var watches: [NSKeyValueObservation] = []

        // 한 번 정하지 않고 계속 지켜본다. SwiftUI는 이 뷰를 놓은 뒤, 여기서 예약한 어떤 일보다 늦은 단계에서 자기 바운스 설정으로 elasticity를 정하므로, 한 번만 정한 값은 되돌아갔다.
        // SwiftUI는 스크롤하는 축(여기서는 세로)만 되돌리지만, 그 사실에 기대지 않도록 다른 축도 지켜본다.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let scroll = enclosingScrollView else { return watches = [] }
            watches = [
                scroll.observe(\.verticalScrollElasticity, options: [.initial, .new]) { scroll, _ in
                    MainActor.assumeIsolated { if scroll.verticalScrollElasticity != .none { scroll.verticalScrollElasticity = .none } }
                },
                scroll.observe(\.horizontalScrollElasticity, options: [.initial, .new]) { scroll, _ in
                    MainActor.assumeIsolated { if scroll.horizontalScrollElasticity != .none { scroll.horizontalScrollElasticity = .none } }
                },
            ]
        }
    }
}
#else
private struct NoBounce: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}

    final class Probe: UIView {
        private var watch: NSKeyValueObservation?

        // Mac의 elasticity처럼 지켜보고, 배치할 때마다 다시 정한다. UIKit은 `bounces`의 KVO를 보장하지 않으므로, 지켜보기가 놓친 변경이 있으면 Mac에서 한 번만 정한 값처럼
        // 페이지가 다시 바운스한다.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scroll = enclosingScrollView else { return watch = nil }
            watch = scroll.observe(\.bounces, options: [.initial, .new]) { scroll, _ in
                MainActor.assumeIsolated { if scroll.bounces { scroll.bounces = false } }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let scroll = enclosingScrollView, scroll.bounces { scroll.bounces = false }
        }

        var enclosingScrollView: UIScrollView? {
            var view = superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            return view as? UIScrollView
        }
    }
}
#endif
