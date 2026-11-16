import AppKit
import Observation
import SwiftUI
import Testing

@testable import Folio

@MainActor @Suite(.serialized)
struct TitleDragTests {
    private let shown = Shown()
    let window: NSWindow
    let host: NSView

    // 줄 전체를 덮는 `TitleDrag` 위에 끌기 gesture를 가진 탭 하나를 둔다. 실제 hover는 화면 밖 창에 보낼 수 없으므로 포인터가 탭에
    // 올라온 것은 `TitleDragHold`를 직접 불러 본다.
    init() {
        let shown = shown
        host = NSHostingView(
            rootView: TitleRow(lead: 0) {
                TabProbe(shown: shown)
            } trailing: {
                EmptyView()
            })
        window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 600, height: Theme.Size.toolbarRow), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = host
    }

    func settle() async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(0.3))
        host.layoutSubtreeIfNeeded()
    }

    var band: TitleDrag.Band? {
        func find(_ view: NSView) -> TitleDrag.Band? {
            (view as? TitleDrag.Band) ?? view.subviews.lazy.compactMap(find).first
        }
        return find(host)
    }

    func hit(x: CGFloat) -> NSView? {
        let point = host.convert(NSPoint(x: x, y: host.bounds.midY), to: host.superview)
        return host.hitTest(point)
    }

    static let onTab: CGFloat = TabProbe.width / 2
    static let empty: CGFloat = 400

    @Test func aHoveredTabStopsTheWindowFromMoving() async throws {
        try await settle()
        let band = try #require(band)
        let hold = try #require(band.hold)
        #expect(hold.window === window && window.isMovable)
        // 누름은 바탕의 NSView가 아니라 그 위의 SwiftUI 탭이 받는다. 창이 끌린 것은 AppKit이 누름을 보내기 전에 창 끌기를 정해서다.
        #expect(hit(x: Self.onTab) === host && hit(x: Self.empty) === band)

        hold.hold(TabProbe.id, true)
        #expect(!window.isMovable)
        hold.hold(TabProbe.id, false)
        #expect(window.isMovable)
    }

    @Test func aHoldLetsGoOfTheWindowItLeaves() async throws {
        try await settle()
        let hold = try #require(band?.hold)
        hold.hold(TabProbe.id, true)
        hold.window = nil
        #expect(window.isMovable)
    }

    @Test func aTabClosedUnderThePointerLetsTheWindowMoveAgain() async throws {
        try await settle()
        let hold = try #require(band?.hold)
        hold.hold(TabProbe.id, true)
        #expect(!window.isMovable)
        shown.tab = false
        try await settle()
        #expect(window.isMovable && !hold.held)
    }
}

@MainActor @Observable private final class Shown {
    var tab = true
}

private struct TabProbe: View {
    let shown: Shown

    static let id = "tab"
    static let width: CGFloat = 80

    var body: some View {
        if shown.tab {
            Color.gray
                .frame(width: Self.width, height: Theme.Size.toolbarButton)
                .contentShape(.rect)
                .gesture(DragGesture())
                .holdsTitleDrag(Self.id)
        }
    }
}
