import FolioDomain
import Foundation
import PropertyBased
import Testing

struct PageTextTests {
    let fig = String(PageText.figure)

    @Test func figuresAreNotWords() {
        let text = "Router \(fig)\(fig) input port\n\(fig) \(fig) \(fig)"
        #expect(PageText.words(text) == 3)
        #expect(PageText.figures(text) == 5)
    }

    @Test func cleanedDropsFiguresAndEmptyLines() {
        let text = "  Network   layer \(fig)\n\(fig)\(fig)\n\n   data plane\tand control\n"
        #expect(PageText.cleaned(text) == "Network layer\ndata plane and control")
        #expect(!PageText.cleaned(text).contains(PageText.figure))
    }

    @Test func titleIsTheLargestTypeAmongTheFirstLines() {
        let lines: [(text: String, size: Double)] = [("4-12", 10), ("  Router architecture  ", 28), ("input ports", 18), ("switching", 18), ("A huge formula", 40)]
        #expect(PageText.title(lines) == "Router architecture")
    }

    @Test func figureOnlyLinesDoNotUseUpTheTitleLines() {
        let lines: [(text: String, size: Double)] = [(fig, 40), ("\(fig) \(fig)", 40), (" ", 50), ("label", 12), ("label", 12), ("label", 12), ("label", 12), ("Middleboxes", 24)]
        #expect(PageText.title(lines) == "label")
        let titled: [(text: String, size: Double)] = [(fig, 40), ("\(fig)\(fig)", 40), ("Middleboxes", 24), ("NAT", 14)]
        #expect(PageText.title(titled) == "Middleboxes")
    }

    @Test func noFontNoTitle() {
        #expect(PageText.title([("words", 0)]) == nil)
        #expect(PageText.title([]) == nil)
    }

    @Test func cleanedTextHasNoFiguresOrBlankLines() async {
        await propertyCheck(input: Gen.element(of: ["a", "b c", "\u{FFFC}", " ", "\n", "\t", "슬라이드"]).map { $0! }.array(of: 0...40)) { parts in
            let cleaned = PageText.cleaned(parts.joined())
            #expect(!cleaned.contains(PageText.figure))
            #expect(cleaned.isEmpty || cleaned.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            #expect(PageText.words(cleaned) == PageText.words(parts.joined()))
        }
    }
}

struct ReadingLimitTests {
    @Test func clampKeepsToTheFile() {
        #expect(ReadingLimit.clamp(nil, count: 24) == 1...24)
        #expect(ReadingLimit.clamp(20...Int.max, count: 24) == 20...24)
        #expect(ReadingLimit.clamp(30...40, count: 24) == nil)
        #expect(ReadingLimit.clamp(nil, count: 0) == nil)
    }

    @Test func aReadStopsAtItsPagesAndSaysWhereToGoOn() {
        let asked = 1...107
        let served = ReadingLimit.served(asked, most: 30)
        #expect(served == 1...30)
        #expect(ReadingLimit.next(after: served, asked: asked, most: 30) == 31...60)
        #expect(ReadingLimit.next(after: 91...107, asked: asked, most: 30) == nil)
        #expect(ReadingLimit.next(after: 61...90, asked: asked, most: 30) == 91...107)
    }

    @Test func theTextBudgetCutsAtAPageButAlwaysServesOne() {
        #expect(ReadingLimit.served(5...20, most: 30, lengths: [10, 10, 10, 10], budget: 25) == 5...6)
        #expect(ReadingLimit.served(5...20, most: 30, lengths: [100, 10], budget: 25) == 5...5)
        #expect(ReadingLimit.served(5...6, most: 30, lengths: [1, 1, 1], budget: 25) == 5...6)
    }

    @Test func servedNeverLeavesTheAskedPages() async {
        await propertyCheck(input: Gen.int(in: 1...50), Gen.int(in: 0...60), Gen.int(in: 1...40), Gen.int(in: 0...500).array(of: 0...70)) { first, span, most, lengths in
            let asked = first...(first + span)
            let served = ReadingLimit.served(asked, most: most, lengths: lengths, budget: 1000)
            #expect(served.lowerBound == asked.lowerBound && served.upperBound <= asked.upperBound)
            #expect(served.count >= 1 && served.count <= most)
            if let next = ReadingLimit.next(after: served, asked: asked, most: most) {
                #expect(next.lowerBound == served.upperBound + 1 && next.upperBound <= asked.upperBound && next.count <= most)
            } else {
                #expect(served.upperBound == asked.upperBound)
            }
        }
    }
}

struct TranscriptWindowTests {
    let transcript = LectureTranscript(locale: "ko-KR", lines: [
        .init(start: 0, end: 5, text: "오늘은 매칭"),
        .init(start: 5, end: 12, text: "홀의 정리를 본다"),
        .init(start: 600, end: 610, text: "증명은 귀납법으로"),
        .init(start: 1200, end: 1205, text: "다음 시간에"),
    ])

    @Test func aSpanKeepsTheLinesSaidInIt() {
        #expect(transcript.window(from: 600, to: 1200).lines.map(\.start) == [600])
        #expect(transcript.window(from: nil, to: 10).lines.map(\.start) == [0, 5])
        #expect(transcript.window(from: 1200, to: nil).lines.map(\.start) == [1200])
        #expect(transcript.window(from: nil, to: nil).next == nil)
    }

    @Test func aLineStillSpokenAtTheStartIsIn() {
        #expect(transcript.window(from: 8, to: 20).lines.map(\.start) == [5])
        #expect(transcript.window(from: 12, to: 20).lines.isEmpty)
    }

    @Test func theBudgetCutsAtALineAndSaysWhereToGoOn() {
        let cut = transcript.window(from: nil, to: nil, budget: 15)
        #expect(cut.lines.map(\.start) == [0])
        #expect(cut.next == 5)
        let rest = transcript.window(from: cut.next, to: nil, budget: 15)
        #expect(rest.lines.first?.start == 5)
        #expect(transcript.window(from: nil, to: nil, budget: 1).lines.count == 1)
    }
}
