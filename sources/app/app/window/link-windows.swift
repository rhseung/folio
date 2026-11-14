import FolioDomain
import SwiftUI

// SwiftUI는 같은 값을 보이는 창이 이미 있으면 새로 열지 않고 그 창을 앞으로 가져온다. 같은 링크를 두 번 요청하면 창이
// 두 개 열려야 하므로 요청마다 ID를 둔다.
struct WindowRequest: Codable, Hashable {
    var id = UUID()
    var link: AppLink
    var course: UUID?
    var history: LinkHistory<Navigator.Entry>?
    var panes: [LinkHistory<Navigator.Entry>]?
    var shares: [Double]?
    var focus: Int?
    var columns: [[String]]?

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension FocusedValues {
    @Entry var navigator: Navigator?
    @Entry var openPlace: (@MainActor (AppLink) -> Void)?
}

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

struct TabCommands: Commands {
    @FocusedValue(\.windowTabs) private var tabs

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(.tabsNew) { tabs?.open() }
                .keyboardShortcut("t")
                .disabled(tabs == nil)
        }
        // 시스템의 닫기(⌘W)를 바꾼다. 그대로 두면 탭 명령이 키를 받기 전에 창 전체가 닫힌다.
        CommandGroup(replacing: .saveItem) {
            Button(.tabsClose) {
                guard NSApp.keyWindow?.sheetParent == nil else { return }
                if let tabs { tabs.closeSelected() } else { NSApp.keyWindow?.performClose(nil) }
            }
            .keyboardShortcut("w")
            Button(.tabsCloseWindow) { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }
    }
}

struct WindowWidth: NSViewRepresentable {
    let changed: @MainActor (CGFloat) -> Void

    func makeNSView(context: Context) -> Probe { Probe(changed: changed) }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed }

    final class Probe: NSView {
        var changed: @MainActor (CGFloat) -> Void
        private var observer: NSObjectProtocol?

        init(changed: @escaping @MainActor (CGFloat) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            // queue 없이 등록해야 창이 알림을 보내는 frame 변경 안에서, 창이 배치되기 전에 실행된다. queue를 주면 다음 차례까지
            // 기다린다.
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: nil) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    self.changed(window.frame.width)
                }
            }
            Task { @MainActor [weak self] in self?.changed(window.frame.width) }
        }
    }
}

@MainActor final class WindowHost {
    weak var window: NSWindow?
}

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

// 포인터 아래에 옆으로 스크롤하는 것이 없을 때만 동작한다. 그렇지 않으면 넓은 PDF나 표가 가로 스크롤을 잃는다. web
// view(노트 미리보기, Claude 패널)는 넓은 표와 코드를 페이지 안에서 스크롤해 AppKit이 알 수 없으므로, web view
// 위에서는 swipe를 web view에 맡긴다.
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
            if event.type == .swipe {
                if event.deltaX > 0 { back() } else if event.deltaX < 0 { forward() }
                return true
            }
            guard event.phase == .began, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
                abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), !scrollsSideways(event)
            else { return false }
            var done = false
            event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount], dampenAmountThresholdMin: -1, max: 1) {
                [weak self] amount, phase, complete, _ in
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
                var view = content.hitTest(content.convert(event.locationInWindow, from: nil))
            else { return false }
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
