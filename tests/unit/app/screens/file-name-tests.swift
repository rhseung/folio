import AppKit
import SwiftUI
import Testing

@testable import Folio

@MainActor
struct FileNameTests {
    static let long = "2_20250123_3분반_Synthesis and analysis of aspirin and salicylic acid, final version.pdf"

    static func height(_ view: some View, width: CGFloat, room: CGFloat = 10_000) -> CGFloat {
        NSHostingController(rootView: view.font(Theme.Typeface.body)).sizeThatFits(in: CGSize(width: width, height: room)).height
    }

    @Test func wrapsToTwoLinesThenStops() {
        let one = Self.height(Text("a.pdf"), width: 200)
        let two = Self.height(Text("a\nb"), width: 200)
        #expect(Self.height(FileName("a.pdf"), width: 200) == one)
        #expect(Self.height(FileName(Self.long), width: 200) == two)
        #expect(Self.height(FileName(Self.long + Self.long), width: 200) == two)
    }

    // 시트의 행처럼 한 줄 높이만 제안받아도 두 줄로 넘긴다.
    @Test func wrapsUnderAOneLineHeightProposal() {
        let one = Self.height(Text("a.pdf"), width: 200)
        let two = Self.height(Text("a\nb"), width: 200)
        #expect(Self.height(FileName(Self.long), width: 200, room: one) == two)
    }

    @Test func narrowWidthsStayOnOneLine() {
        let one = Self.height(Text("a.pdf"), width: 160)
        for width in [160.0, 64, 40, 16] {
            #expect(Self.height(FileName(Self.long, lineLimit: 1), width: width) == one)
        }
        for width in [40.0, 16] {
            #expect(Self.height(FileName(Self.long), width: width) == one)
        }
    }
}
