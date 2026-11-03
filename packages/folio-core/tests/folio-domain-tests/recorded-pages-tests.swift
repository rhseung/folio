import FolioDomain
import Foundation
import PropertyBased
import Testing

struct RecordedPagesTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)
    let slides = UUID()
    let other = UUID()

    func recording(_ pages: [PageVisit], duration: TimeInterval = 600, session: UUID? = nil) -> Recording {
        Recording(device: device, at: now, sessionId: session, file: "Recordings/5주차-1.m4a", duration: duration, pages: pages)
    }

    @Test func pagesPassedOnTheWayDoNotCount() {
        // Paging from 3 to 9 to find the slide, then staying.
        let r = recording([
            PageVisit(at: 0, materialId: slides, page: 3), PageVisit(at: 100, materialId: slides, page: 4), PageVisit(at: 101, materialId: slides, page: 5),
            PageVisit(at: 102, materialId: slides, page: 12), PageVisit(at: 103, materialId: slides, page: 9),
        ])
        #expect(r.viewedPages() == [SessionMaterial(materialId: slides, firstPage: 3, lastPage: 9)])
    }

    @Test func aPageCountsFromTwentySeconds() {
        let visits = [PageVisit(at: 0, materialId: slides, page: 2), PageVisit(at: 19, materialId: slides, page: 3), PageVisit(at: 40, materialId: slides, page: nil)]
        #expect(recording(visits).viewedPages() == [SessionMaterial(materialId: slides, firstPage: 3, lastPage: 3)])
        // Closing the file ends its last page's time; the rest of the class doesn't count toward it.
        #expect(recording([PageVisit(at: 0, materialId: slides, page: 2), PageVisit(at: 10, materialId: slides, page: nil)]).viewedPages().isEmpty)
    }

    @Test func theLastPageRunsToTheAudiosEnd() {
        #expect(recording([PageVisit(at: 0, materialId: slides, page: 7)], duration: 19).viewedPages().isEmpty)
        #expect(recording([PageVisit(at: 0, materialId: slides, page: 7)], duration: 30).viewedPages() == [SessionMaterial(materialId: slides, firstPage: 7, lastPage: 7)])
    }

    @Test func filesKeepTheOrderTheyWereOpenedIn() {
        let r = recording([
            PageVisit(at: 0, materialId: other, page: 10), PageVisit(at: 60, materialId: slides, page: 1),
            PageVisit(at: 120, materialId: other, page: 2), PageVisit(at: 180, materialId: other, page: nil),
        ])
        #expect(r.viewedPages() == [SessionMaterial(materialId: other, firstPage: 2, lastPage: 10), SessionMaterial(materialId: slides, firstPage: 1, lastPage: 1)])
    }

    @Test func aVisitIsKeptOnlyWhenTheScreenChanges() {
        var r = recording([])
        #expect(r.visit(slides, page: nil, at: 0) == nil)
        r.pages.append(r.visit(slides, page: 4, at: 5)!)
        #expect(r.visit(slides, page: 4, at: 9) == nil)
        // Another file's viewer closing after this one opened is not this one closing.
        #expect(r.visit(other, page: nil, at: 10) == nil)
        #expect(r.visit(slides, page: 5, at: 11) == PageVisit(at: 11, materialId: slides, page: 5))
        r.pages.append(r.visit(slides, page: nil, at: 12)!)
        #expect(r.visit(slides, page: nil, at: 13) == nil)
    }

    @Test func aRecordingSavedBeforePagesWereKeptReadsAsNone() throws {
        let old = Data(#"{"id":"A0000000-0000-4000-8000-0000000000E1","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","updatedBy":"A0000000-0000-4000-8000-0000000000E2","file":"Recordings/a.m4a","startedAt":"2026-01-01T00:00:00Z","duration":60,"bookmarks":[]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(Recording.self, from: old).pages.isEmpty)
    }

    @Test func viewedPagesAddOnlyToFilesTheSessionHasNoLinkTo() {
        var file = CourseFile(course: Course(device: device, at: now, title: "컴파일러"))
        let a = Material(device: device, at: now, path: "Lectures/a.pdf", role: .lecture, status: .classified)
        let b = Material(device: device, at: now, path: "Lectures/b.pdf", role: .lecture, status: .classified)
        file.materials = [a, b]
        file.sessions = [Session(device: device, at: now, week: 5, date: now)]
        let session = file.sessions[0].id
        file.linkMaterial(a.id, session: session, firstPage: 1, lastPage: 3)
        let r = recording([PageVisit(at: 0, materialId: a.id, page: 8), PageVisit(at: 60, materialId: b.id, page: 2),
                           PageVisit(at: 120, materialId: b.id, page: 6), PageVisit(at: 180, materialId: UUID(), page: 1)], session: session)
        #expect(file.linkViewedPages(of: r) == 1)
        #expect(file.sessions[0].materials == [SessionMaterial(materialId: a.id, firstPage: 1, lastPage: 3), SessionMaterial(materialId: b.id, firstPage: 2, lastPage: 6)])
        #expect(file.materials[1].sessionIds == [session])
        // Again changes nothing.
        #expect(file.linkViewedPages(of: r) == 0)
    }

    static let visits = zip(Gen.int(in: 0...90), Gen.int(in: 0...2), Gen.int(in: 0...12)).array(of: 0...30)

    /// Every range is made of pages that were on screen for the dwell, and covers every such page of its file.
    @Test func rangesSpanExactlyTheDwelledPages() async {
        let files = [UUID(), UUID()]
        await propertyCheck(input: Self.visits) { steps in
            var at: TimeInterval = 0
            let pages = steps.map { gap, file, page in
                at += TimeInterval(gap)
                return PageVisit(at: at, materialId: files[min(file, 1)], page: file == 2 ? nil : page)
            }
            let r = recording(pages, duration: at + 30)
            var dwelled: [UUID: [Int]] = [:]
            for (i, v) in pages.enumerated() {
                guard let page = v.page else { continue }
                let left = i + 1 < pages.count ? pages[i + 1].at : r.duration
                if left - v.at >= Recording.pageDwell { dwelled[v.materialId, default: []].append(page) }
            }
            let ranges = r.viewedPages()
            #expect(Set(ranges.map(\.materialId)) == Set(dwelled.keys))
            #expect(ranges.count == Set(ranges.map(\.materialId)).count)
            for range in ranges {
                let seen = dwelled[range.materialId] ?? []
                #expect(range.firstPage == seen.min() && range.lastPage == seen.max())
            }
        }
    }
}
