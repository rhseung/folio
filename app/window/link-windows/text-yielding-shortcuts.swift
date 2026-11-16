import FolioDomain
import SwiftUI

#if os(macOS)
import AppKit

// 글 칸에 양보하는 키(⌘←·⌘→)를 받는다. AppKit은 메뉴 키를 글 칸보다 먼저 처리하므로 이 키들은 메뉴에 두지 않고,
// 글을 쓰는 칸에 포커스가 없을 때만 받는다. iPad는 메뉴 키를 글 칸보다 늦게 받아 메뉴에 둔다(`NavigationCommands`).
struct TextYieldingShortcuts: NSViewRepresentable {
    let run: @MainActor (ShortcutID) -> Bool

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.run = run
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) { view.run = run }

    static func dismantleNSView(_ view: KeyView, coordinator: ()) { view.stop() }

    static let keys: [KeyCombo: ShortcutID] = Dictionary(
        ShortcutTable.standard.flatMap { s in s.bindings.filter(\.yieldsToText).map { ($0.combo, s.id) } },
        uniquingKeysWith: { first, _ in first })

    final class KeyView: NSView {
        var run: @MainActor (ShortcutID) -> Bool = { _ in false }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                nonisolated(unsafe) let event = event
                let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
                return consumed ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func consumes(_ event: NSEvent) -> Bool {
            guard event.window === window, let window, let combo = KeyCombo(event), let id = TextYieldingShortcuts.keys[combo]
            else { return false }
            if let text = window.firstResponder as? NSTextView, text.isEditable { return false }
            return run(id)
        }
    }
}

#endif
