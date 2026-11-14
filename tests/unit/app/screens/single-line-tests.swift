import AppKit
import SwiftUI
import Testing

@testable import Folio

@MainActor
struct SingleLineTests {
    static let long = String(repeating: "아주 긴 이름 ", count: 12)
    static let short = "이름"

    static func heights(width: CGFloat = 160, _ make: (String) -> some View) -> (short: CGFloat, long: CGFloat) {
        func height(_ text: String) -> CGFloat {
            NSHostingController(rootView: make(text).font(Theme.Typeface.body)).sizeThatFits(in: CGSize(width: width, height: 10_000))
                .height
        }
        return (height(short), height(long))
    }

    @Test func columnRow() {
        let h = Self.heights { ColumnRow(title: $0, symbol: "doc", chosen: false) { Text("16") } }
        #expect(h.long == h.short)
    }

    @Test func blockHeading() {
        let h = Self.heights { Block($0) { EmptyView() } }
        #expect(h.long == h.short)
    }

    @Test func blockNoteMovesUnderTheTitle() {
        let block = { (title: String) in Block(title: title, note: "16개", trailing: { Text("추가") }) { EmptyView() } }
        let under = Self.heights { block($0) }
        #expect(under.long > under.short)
        let longer = Self.heights { block($0 + Self.long) }
        #expect(longer.long == under.long)
    }

    @Test func formRowLabel() {
        let h = Self.heights(width: 200) { FormRow(label: $0) { Text("값") } }
        #expect(h.long == h.short)
    }

    @Test func pageBar() {
        let h = Self.heights { name in
            PageBar {
                Text(name); Text("21 / 31")
            } trailing: {
                Text(name)
            }
        }
        #expect(h.long == h.short)
    }

    @Test func noticeAndEmptyCards() {
        let notice = Self.heights { NoticeCard(title: $0 + Self.long) { Button("정리") {} } }
        #expect(notice.long == notice.short)
        let empty = Self.heights { EmptyCard(symbol: "tray", title: $0) }
        #expect(empty.long == empty.short)
    }

    @Test func labels() {
        let caption = Self.heights { Caption($0) }
        #expect(caption.long == caption.short)
        let header = Self.heights { PageHeader(title: $0) }
        #expect(header.long == header.short)
        let chipTabs = Self.heights { ChipTabs(selection: .constant(0), options: [(0, $0)]) }
        #expect(chipTabs.long == chipTabs.short)
        // 텍스트 레이블은 ghost 레이블 스타일까지 닿지 않으므로, 버튼 스타일도 줄 수를 제한해야 한다.
        let ghost = Self.heights { Button($0) {}.buttonStyle(.ghost) }
        #expect(ghost.long == ghost.short)
        let ghostLabel = Self.heights { name in
            Button {
            } label: {
                Label(name, systemImage: "plus")
            }.buttonStyle(.ghost)
        }
        #expect(ghostLabel.long == ghostLabel.short)
    }
}
