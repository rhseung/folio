import Foundation
import PropertyBased
import Testing

@testable import FolioMarkdown

struct InlineMarkTests {
    func toggle(_ mark: InlineMark, _ s: String) -> String {
        let m = Marked(s)
        return Marked.show(m.text, SourceEditing.toggle(mark, in: m.text, selection: m.selection))
    }

    @Test func wrapsAndUnwrapsTheSelection() {
        #expect(toggle(.bold, "그래프 «매칭» 이론") == "그래프 **«매칭»** 이론")
        #expect(toggle(.bold, "그래프 **«매칭»** 이론") == "그래프 «매칭» 이론")
        #expect(toggle(.bold, "그래프 «**매칭**» 이론") == "그래프 «매칭» 이론")
        #expect(toggle(.italic, "그래프 «매칭» 이론") == "그래프 *«매칭»* 이론")
        #expect(toggle(.italic, "그래프 *«매칭»* 이론") == "그래프 «매칭» 이론")
    }

    @Test func boldAndItalicStackOnThreeStars() {
        #expect(toggle(.italic, "**«매칭»**") == "***«매칭»***")
        #expect(toggle(.bold, "*«매칭»*") == "***«매칭»***")
        #expect(toggle(.italic, "***«매칭»***") == "**«매칭»**")
        #expect(toggle(.bold, "***«매칭»***") == "*«매칭»*")
    }

    @Test func spacesAtTheEdgesStayOutside() {
        #expect(toggle(.bold, "그래프«매칭 »이론") == "그래프**«매칭»** 이론")
    }

    @Test func anEmptySelectionOpensAPairAndClosesAnEmptyOne() {
        #expect(toggle(.bold, "그래프 |") == "그래프 **|**")
        #expect(toggle(.bold, "그래프 **|**") == "그래프 |")
        #expect(toggle(.italic, "그래프 |") == "그래프 *|*")
    }

    static let word = Gen.int(in: 0...5).array(of: 1...6).map { $0.map { ["가", "b", "수", "x", "1", "식"][$0] }.joined() }

    // 같은 표시를 두 번 켜고 끄면 원래 글과 선택으로 돌아온다.
    @Test func togglingTwiceGivesTheTextBack() async {
        await propertyCheck(input: Self.word, Self.word, Self.word, Gen.int(in: 0...1)) { before, picked, after, which in
            let mark: InlineMark = which == 0 ? .bold : .italic
            let text = (before + " " + picked + " " + after) as NSString
            let selection = NSRange(location: (before + " ").utf16.count, length: picked.utf16.count)
            let once = SourceEditing.toggle(mark, in: text, selection: selection)
            let middle = once.applied(to: text) as NSString
            let twice = SourceEditing.toggle(mark, in: middle, selection: once.selection)
            #expect(twice.applied(to: middle) == text as String)
            #expect(twice.selection == selection)
        }
    }
}
