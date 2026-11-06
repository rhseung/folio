import FolioDomain
import SwiftUI

/// A window a link asked for. It carries an ID of its own: SwiftUI brings forward a window already showing the same
/// value instead of opening another, and asking twice for one link should give two.
struct WindowRequest: Codable, Hashable {
    var id = UUID()
    var link: AppLink
    var course: UUID?
    /// A tab moved out to this window brings where it has been.
    var history: LinkHistory<Navigator.Entry>?

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension FocusedValues {
    /// The key window's history, for the menu bar's back and forward.
    @Entry var navigator: Navigator?
}

/// Back and forward in the toolbar. A click steps once; holding the button lists the places it would step through.
struct HistoryButtons: View {
    let navigator: Navigator
    let title: (Navigator.Entry) -> String

    static let width = Theme.Size.toolbarButton * 2

    var body: some View {
        HStack(spacing: 0) {
            step(back: true)
            step(back: false)
        }
        .toolbarGroup()
        .buttonStyle(.toolbar)
        .menuStyle(.button)
    }

    func step(back: Bool) -> some View {
        let list = back ? navigator.backList : navigator.forwardList
        return Menu {
            ForEach(Array(list.enumerated()), id: \.offset) { i, entry in
                Button(title(entry)) { if back { navigator.back(i + 1) } else { navigator.forward(i + 1) } }
            }
        } label: {
            Label(back ? .navigationBack : .navigationForward, systemImage: back ? "chevron.backward" : "chevron.forward")
        } primaryAction: {
            if back { navigator.back() } else { navigator.forward() }
        }
        .menuIndicator(.hidden)
        .disabled(list.isEmpty)
        .help(Text(back ? .navigationBackHelp : .navigationForwardHelp))
    }
}

/// ⌘[ and ⌘] in the menu bar, for the window in front, as in Finder's 이동 menu; on the Mac, moving between the
/// window's tabs too.
struct NavigationCommands: Commands {
    @FocusedValue(\.navigator) private var navigator
    #if os(macOS)
    @FocusedValue(\.windowTabs) private var tabs
    #endif

    var body: some Commands {
        CommandMenu(Text(.navigationMenu)) {
            Button(.navigationBack) { navigator?.back() }
                .keyboardShortcut("[")
                .disabled(navigator?.history.canGoBack != true)
            Button(.navigationForward) { navigator?.forward() }
                .keyboardShortcut("]")
                .disabled(navigator?.history.canGoForward != true)
            #if os(macOS)
            Divider()
            Button(.tabsNext) { tabs?.selectNext() }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled((tabs?.count ?? 0) < 2)
            Button(.tabsPrevious) { tabs?.selectPrevious() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled((tabs?.count ?? 0) < 2)
            Menu(String(localized: .tabsPick)) {
                ForEach(1...8, id: \.self) { n in
                    Button(.tabsNumber(n)) { tabs?.select(number: n) }
                        .keyboardShortcut(KeyEquivalent(Character(String(n))))
                        .disabled((tabs?.count ?? 0) < n)
                }
                Button(.tabsLast) { tabs?.select(number: 9) }
                    .keyboardShortcut("9")
                    .disabled((tabs?.count ?? 0) < 2)
            }
            #endif
        }
    }
}

#if os(macOS)
import AppKit
import WebKit

/// ⌘T and ⌘W work on the window's own tabs, as in Safari: the window's close moves to ⇧⌘W, and ⌘W on the last tab
/// closes the window.
struct TabCommands: Commands {
    @FocusedValue(\.windowTabs) private var tabs

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(.tabsNew) { tabs?.open() }
                .keyboardShortcut("t")
                .disabled(tabs == nil)
        }
        // Replaces the system's 닫기 (⌘W), which would close the whole window before the tab's command saw the key.
        CommandGroup(replacing: .saveItem) {
            Button(.tabsClose) {
                // Not while a sheet is up: the tab would close under it, sheet and all.
                guard NSApp.keyWindow?.sheetParent == nil else { return }
                if let tabs { tabs.closeSelected() } else { NSApp.keyWindow?.performClose(nil) }
            }
            .keyboardShortcut("w")
            Button(.tabsCloseWindow) { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }
    }
}

/// Where a toolbar item begins across its window. The row places its items itself: the first after the window's
/// buttons (gone in full screen), the last pushed to the end by a flexible space. Nil while the item is out of the
/// window, dropped into the row's overflow menu.
struct WindowOffset: NSViewRepresentable {
    let changed: @MainActor (CGFloat?) -> Void

    func makeNSView(context: Context) -> Probe { Probe(changed: changed) }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed }

    final class Probe: NSView {
        var changed: @MainActor (CGFloat?) -> Void
        private var reported: CGFloat??
        private var observers: [NSObjectProtocol] = []

        init(changed: @escaping @MainActor (CGFloat?) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
            if let window {
                // The item moves without this view's own frame changing, so the window's changes are watched too.
                observers = [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification].map { name in
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.report() }
                    }
                }
            }
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// On the next turn: while the row is laying out, its items are still where they were.
        func report() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let x = window.map { _ in convert(NSPoint.zero, to: nil).x }
                guard reported != .some(x) else { return }
                reported = .some(x)
                changed(x)
            }
        }
    }
}

/// The window a view is in, kept weakly: the window owns the view.
@MainActor final class WindowHost {
    weak var window: NSWindow?
}

/// Finds the window a view is in once it has one.
struct WindowReader: NSViewRepresentable {
    let found: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Probe(found: found) }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Probe: NSView {
        let found: @MainActor (NSWindow) -> Void
        init(found: @escaping @MainActor (NSWindow) -> Void) {
            self.found = found
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found(window) }
        }
    }
}

/// A two-finger swipe on the trackpad goes back or forward, as in Safari and Finder. Only where nothing under the
/// pointer scrolls sideways itself: a wide PDF or a table would otherwise lose its own horizontal scroll. A web view
/// (the note preview, the Claude panel) scrolls its wide tables and code inside the page, out of AppKit's sight, so
/// over one the swipe is left to it.
struct SwipeNavigation: NSViewRepresentable {
    let back: @MainActor () -> Void
    let forward: @MainActor () -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.back = back
        view.forward = forward
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.back = back
        view.forward = forward
    }

    static func dismantleNSView(_ view: SwipeView, coordinator: ()) { view.stop() }

    final class SwipeView: NSView {
        var back: @MainActor () -> Void = {}
        var forward: @MainActor () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
                // Local monitors run on the main thread, with the event the app is handling there.
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
            guard event.window === window else { return false }
            // "Swipe between pages" set to three fingers sends a swipe; to two, the scroll that starts one.
            if event.type == .swipe {
                if event.deltaX > 0 { back() } else if event.deltaX < 0 { forward() }
                return true
            }
            guard event.phase == .began, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), !scrollsSideways(event) else { return false }
            var done = false
            event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount], dampenAmountThresholdMin: -1, max: 1) { [weak self] amount, phase, complete, _ in
                guard !done, phase == .ended, abs(amount) >= 1 else { return }
                done = true
                MainActor.assumeIsolated {
                    if amount > 0 { self?.back() } else { self?.forward() }
                }
            }
            return false
        }

        private func scrollsSideways(_ event: NSEvent) -> Bool {
            guard let content = window?.contentView,
                  var view = content.hitTest(content.convert(event.locationInWindow, from: nil)) else { return false }
            var ancestor: NSView? = view
            while let a = ancestor {
                if a is WKWebView { return true }
                ancestor = a.superview
            }
            while let scroll = view.enclosingScrollView {
                if let document = scroll.documentView, document.frame.width > scroll.contentView.bounds.width + 1 { return true }
                view = scroll
            }
            return false
        }
    }
}
#endif
