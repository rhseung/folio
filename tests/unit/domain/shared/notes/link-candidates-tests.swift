import FolioDomain
import Foundation
import PropertyBased
import Testing

struct LinkCandidatesTests {
    let here = UUID(), there = UUID()

    func hit(_ kind: SearchKind, _ course: UUID, _ title: String, id: UUID = UUID()) -> SearchHit {
        SearchHit(item: SearchItem(kind: kind, courseId: course, id: id, title: title))
    }

    @Test func theCourseWrittenInComesFirst() {
        let own = UUID()
        let hits = [
            hit(.note, there, "매칭 정리"), hit(.note, here, "매칭"), hit(.material, there, "05_Matchings.pdf"),
            hit(.note, here, "지금 노트", id: own), hit(.exam, here, "중간고사"),
        ]
        let ordered = LinkCandidates.order(hits, course: here, excluding: own)
        #expect(ordered.map(\.item.title) == ["매칭", "중간고사", "매칭 정리", "05_Matchings.pdf"])
    }

    @Test func theLastPageSeenComesFirst() {
        #expect(LinkCandidates.pages(count: 5, last: 3, typed: "") == [3, 1, 2, 4, 5])
        #expect(LinkCandidates.pages(count: 12, last: 3, typed: "1") == [1, 10, 11, 12])
        #expect(LinkCandidates.pages(count: 12, last: 12, typed: "1") == [12, 1, 10, 11])
        #expect(LinkCandidates.pages(count: 2, last: 9, typed: "") == [1, 2])
        #expect(LinkCandidates.pages(count: nil, last: 4, typed: "") == [4])
        #expect(LinkCandidates.pages(count: nil, last: 4, typed: "17") == [17])
        #expect(LinkCandidates.pages(count: 0, last: nil, typed: "") == [])
        #expect(LinkCandidates.pages(count: 500, last: nil, typed: "", limit: 3) == [1, 2, 3])
    }

    @Test func pagesStayInTheFileAndAppearOnce() async {
        await propertyCheck(input: Gen.int(in: 0...300), Gen.int(in: -2...320), Gen.int(in: 0...400)) { count, last, typed in
            let pages = LinkCandidates.pages(count: count, last: last, typed: typed == 0 ? "" : String(typed))
            #expect(Set(pages).count == pages.count)
            #expect(pages.allSatisfy { $0 >= 1 && $0 <= count })
            if (1...max(count, 1)).contains(last), count >= 1, typed == 0 { #expect(pages.first == last) }
        }
    }

    @Test func aNewNoteIsOfferedForANameNoNoteHas() {
        #expect(LinkCandidates.offersNewNote("최대 매칭", titles: ["매칭"]))
        #expect(!LinkCandidates.offersNewNote("매칭 ", titles: ["매칭"]))
        #expect(!LinkCandidates.offersNewNote("Matching", titles: ["matching"]))
        #expect(!LinkCandidates.offersNewNote("  ", titles: []))
        #expect(!LinkCandidates.offersNewNote("note:6F96", titles: []))
    }
}
