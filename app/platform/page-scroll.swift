import SwiftUI

extension View {
    // SwiftUI can only stop the bounce when the content fits (`scrollBounceBehavior(.basedOnSize)`); a page longer
    // than the window still stretched past its top and bottom, pulling its backdrop off the panel's edge. So the
    // platform scroll view enclosing this content is told not to bounce at all.
    func pageScrollWithoutBounce() -> some View { background { NoBounce() } }
}

#if os(macOS)
private struct NoBounce: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}

    final class Probe: NSView {
        private var watch: NSKeyValueObservation?

        // Watched, not set once: SwiftUI sets the scroll view's elasticity from its own bounce behavior after this view
        // is placed, on a later pass than anything scheduled here, and that undid a value set only once.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let scroll = enclosingScrollView else { return }
            scroll.horizontalScrollElasticity = .none
            watch = scroll.observe(\.verticalScrollElasticity, options: [.initial, .new]) { scroll, _ in
                MainActor.assumeIsolated {
                    if scroll.verticalScrollElasticity != .none { scroll.verticalScrollElasticity = .none }
                }
            }
        }
    }
}
#else
private struct NoBounce: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}

    final class Probe: UIView {
        private var watch: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view = superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            guard let scroll = view as? UIScrollView else { return }
            watch = scroll.observe(\.bounces, options: [.initial, .new]) { scroll, _ in
                MainActor.assumeIsolated {
                    if scroll.bounces { scroll.bounces = false }
                }
            }
        }
    }
}
#endif
