import FolioDomain
import Foundation
import PropertyBased
import Testing

struct LectureProgressTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_793_149_200)
    let day: TimeInterval = 86_400

    /// Three classes a week apart and two lecture files.
    func course() -> CourseFile {
        var file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        file.materials = ["Lectures/06_Flows.pdf", "Lectures/05_Matchings.pdf", "Textbooks/West.pdf"].map {
            Material(device: device, at: now, path: $0, role: MaterialRole(path: $0), status: .classified)
        }
        file.sessions = (0..<3).map { Session(device: device, at: now, week: 9 + $0, date: now + Double($0) * 7 * day) }
        return file
    }

    var matchings: (CourseFile) -> UUID { { $0.materials[1].id } }
    var flows: (CourseFile) -> UUID { { $0.materials[0].id } }

    // MARK: Progress of one file

    @Test func spansSplitWhereTheClassesChange() {
        var f = course()
        let m = matchings(f)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 12)
        f.linkMaterial(m, session: f.sessions[1].id, firstPage: 10, lastPage: 20)
        #expect(f.lectureProgress(of: m, pageCount: 30) == [
            LectureSpan(firstPage: 1, lastPage: 9, sessions: [f.sessions[0].id]),
            LectureSpan(firstPage: 10, lastPage: 12, sessions: [f.sessions[0].id, f.sessions[1].id]),
            LectureSpan(firstPage: 13, lastPage: 20, sessions: [f.sessions[1].id]),
            LectureSpan(firstPage: 21, lastPage: 30, sessions: []),
        ])
        // Without the count, the file ends where the classes do.
        #expect(f.lectureProgress(of: m, pageCount: nil).last == LectureSpan(firstPage: 13, lastPage: 20, sessions: [f.sessions[1].id]))
    }

    @Test func aCancelledClassOrAnUnrangedLinkCoversNoPage() {
        var f = course()
        let m = matchings(f)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 3, lastPage: 5)
        f.linkMaterial(m, session: f.sessions[1].id)
        f.sessions[2].isCancelled = true
        f.linkMaterial(m, session: f.sessions[2].id, firstPage: 1, lastPage: 8)
        #expect(f.lectureProgress(of: m, pageCount: 6) == [
            LectureSpan(firstPage: 1, lastPage: 2, sessions: []),
            LectureSpan(firstPage: 3, lastPage: 5, sessions: [f.sessions[0].id]),
            LectureSpan(firstPage: 6, lastPage: 6, sessions: []),
        ])
        #expect(f.unrangedSessions(of: m).map(\.id) == [f.sessions[1].id])
        #expect(course().lectureProgress(of: m, pageCount: nil).isEmpty)
    }

    @Test func aRangePastTheCountIsCut() {
        var f = course()
        let m = matchings(f)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 8, lastPage: 40)
        #expect(f.lectureProgress(of: m, pageCount: 10).last == LectureSpan(firstPage: 8, lastPage: 10, sessions: [f.sessions[0].id]))
    }

    static let ranges = zip(Gen.int(in: 0...2), Gen.int(in: 1...25), Gen.int(in: 0...10)).array(of: 0...6)

    /// The spans tile the file from page 1, neighbors differ, and each page lists exactly the classes whose range holds it.
    @Test func spansTileTheFile() async {
        await propertyCheck(input: Self.ranges, Gen.int(in: 1...30)) { links, count in
            var f = course()
            let m = matchings(f)
            for (s, first, length) in links { f.linkMaterial(m, session: f.sessions[s].id, firstPage: first, lastPage: first + length) }
            let spans = f.lectureProgress(of: m, pageCount: count)
            #expect(spans.first?.firstPage == 1 && spans.last?.lastPage == count)
            for (a, b) in zip(spans, spans.dropFirst()) {
                #expect(b.firstPage == a.lastPage + 1)
                #expect(a.sessions != b.sessions)
            }
            for span in spans {
                for page in span.firstPage...span.lastPage {
                    let covering = f.sessions.filter { s in s.materials.contains { $0.materialId == m && ($0.firstPage!...$0.lastPage!).contains(page) } }
                    #expect(Set(span.sessions) == Set(covering.map(\.id)))
                }
            }
        }
    }

    // MARK: One class per page

    @Test func sectionsAreEachClassesPagesInPageOrder() {
        var f = course()
        let m = matchings(f)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 9, lastPage: 40)
        f.linkMaterial(m, session: f.sessions[1].id, firstPage: 1, lastPage: 4)
        f.sessions[2].isCancelled = true
        f.linkMaterial(m, session: f.sessions[2].id, firstPage: 5, lastPage: 6)
        // Cut at the count as the progress is, and a cancelled class has none.
        #expect(f.progressSections(of: m, pageCount: 24).map(\.session) == [f.sessions[1].id, f.sessions[0].id])
        #expect(f.progressSections(of: m, pageCount: 24).map(\.pages) == [1...4, 9...24])
        #expect(course().progressSections(of: m, pageCount: 24).isEmpty)
    }

    @Test func classesSharingAPageOverlap() {
        var f = course()
        let (m, book) = (matchings(f), f.materials[2].id)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 5)
        // Meeting end to end is fine; sharing page 5 is not.
        f.linkMaterial(m, session: f.sessions[1].id, firstPage: 6, lastPage: 9)
        #expect(f.progressOverlaps().isEmpty)
        f.linkMaterial(m, session: f.sessions[2].id, firstPage: 5, lastPage: 7)
        let found = f.progressOverlaps().map { [$0.earlier.session.id, $0.later.session.id] }
        #expect(found == [[f.sessions[0].id, f.sessions[2].id], [f.sessions[1].id, f.sessions[2].id]])
        // A cancelled class taught nothing, and a textbook is read over and over.
        f.sessions[2].isCancelled = true
        f.linkMaterial(book, session: f.sessions[0].id, firstPage: 1, lastPage: 50)
        f.linkMaterial(book, session: f.sessions[1].id, firstPage: 1, lastPage: 50)
        #expect(f.progressOverlaps().isEmpty)
    }

    @Test func aSaveThatOverlapsIsRefusedNamingTheOtherClass() {
        var before = course()
        let m = matchings(before)
        before.linkMaterial(m, session: before.sessions[0].id, firstPage: 16, lastPage: 18)
        var after = before
        after.linkMaterial(m, session: after.sessions[1].id, firstPage: 17, lastPage: 21)
        let refused = CourseFile.model.newViolation(before: before, after: after)
        #expect(refused?.rule == "Session.progressOverlap")
        #expect(refused?.message.contains(before.day(of: before.sessions[0], calendar: .current)) == true)
        #expect(refused?.message.contains("16–18쪽") == true && refused?.message.contains("17–21쪽") == true)
        #expect(refused?.message.contains("05_Matchings.pdf") == true)
        var clear = before
        clear.linkMaterial(m, session: clear.sessions[1].id, firstPage: 19, lastPage: 21)
        #expect(CourseFile.model.newViolation(before: before, after: clear) == nil)
    }

    /// The rule's overlaps are exactly the pairs of classes that name a common page of a lecture file.
    @Test func overlapsAreThePairsSharingAPage() async {
        await propertyCheck(input: Self.ranges) { links in
            var f = course()
            let m = matchings(f)
            for (s, first, length) in links { f.linkMaterial(m, session: f.sessions[s].id, firstPage: first, lastPage: first + length) }
            let ranges = f.sessions.map { s in s.materials.first { $0.materialId == m }?.pages }
            var expected: [[UUID]] = []
            for i in ranges.indices {
                for j in ranges.indices where i < j {
                    if let a = ranges[i], let b = ranges[j], (1...40).contains(where: { a.contains($0) && b.contains($0) }) {
                        expected.append([f.sessions[i].id, f.sessions[j].id])
                    }
                }
            }
            #expect(f.progressOverlaps().map { [$0.earlier.session.id, $0.later.session.id] } == expected)
        }
    }

    // MARK: A new range on the page strip

    var seoul: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    /// The classes held so far, latest first, leaving out those with pages of the file and cancelled ones. `now` is
    /// 10:00 in Seoul, so an hour after the second class the third, a week on, is not held yet.
    @Test func aNewRangeIsOfferedToHeldClassesWithoutPages() {
        var f = course()
        let m = matchings(f)
        let at = now + 7 * day + 3600
        func offered(_ f: CourseFile, at: Date) -> [UUID] {
            f.sessionsForNewRange(of: m, now: at, settings: Settings(), calendar: seoul).map(\.id)
        }
        #expect(offered(f, at: at) == [f.sessions[1].id, f.sessions[0].id])

        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 5)
        // Linked without pages, or with pages of another file, a class has none of this one yet.
        f.linkMaterial(m, session: f.sessions[1].id)
        f.linkMaterial(flows(f), session: f.sessions[1].id, firstPage: 1, lastPage: 3)
        #expect(offered(f, at: at) == [f.sessions[1].id])

        f.sessions[1].isCancelled = true
        #expect(offered(f, at: at).isEmpty)
    }

    /// Today's class counts before it starts: the study day decides, not the clock.
    @Test func aNewRangeIsOfferedToTodaysClassBeforeItStarts() {
        let f = course()
        let morning = f.sessions[2].date - 3600
        let offered = f.sessionsForNewRange(of: matchings(f), now: morning, settings: Settings(), calendar: seoul).map(\.id)
        #expect(offered == [f.sessions[2].id, f.sessions[1].id, f.sessions[0].id])
    }

    // MARK: The end-of-class prompt

    @Test func theNextClassPicksUpAfterTheLastOne() {
        var f = course()
        let m = matchings(f)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 12)
        let viewed = [SessionMaterial(materialId: m, firstPage: 11, lastPage: 21)]
        #expect(f.resumePage(of: m, for: f.sessions[1]) == 13)
        #expect(f.suggestedProgress(for: f.sessions[1], viewed: viewed) == [SessionMaterial(materialId: m, firstPage: 13, lastPage: 21)])
        // The most recent class before, not the furthest: the third class follows the second, which went back.
        f.linkMaterial(m, session: f.sessions[1].id, firstPage: 5, lastPage: 9)
        #expect(f.resumePage(of: m, for: f.sessions[2]) == 10)
        // A class's own range isn't where it picks up from.
        #expect(f.resumePage(of: m, for: f.sessions[0]) == nil)
    }

    @Test func aFileNoClassHasReachedStartsAtItsFirstPage() {
        let f = course()
        let m = matchings(f)
        #expect(f.suggestedProgress(for: f.sessions[0], viewed: [SessionMaterial(materialId: m, firstPage: 4, lastPage: 9)])
            == [SessionMaterial(materialId: m, firstPage: 1, lastPage: 9)])
    }

    @Test func aRecapIsSuggestedNoPages() {
        var f = course()
        let m = matchings(f)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 20)
        // The pages gone over belong to the class that taught them.
        #expect(f.suggestedProgress(for: f.sessions[1], viewed: [SessionMaterial(materialId: m, firstPage: 15, lastPage: 18)])
            == [SessionMaterial(materialId: m)])
    }

    @Test func aSuggestionStopsBeforeALaterClassesPages() {
        var f = course()
        let m = matchings(f)
        // The class in between is filled in after the one following it already saved its pages.
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 6)
        f.linkMaterial(m, session: f.sessions[2].id, firstPage: 11, lastPage: 15)
        #expect(f.suggestedProgress(for: f.sessions[1], viewed: [SessionMaterial(materialId: m, firstPage: 5, lastPage: 13)])
            == [SessionMaterial(materialId: m, firstPage: 7, lastPage: 10)])
    }

    /// Whatever the other classes took and the recording saw, a suggestion never names a page another class took.
    @Test func aSuggestionNeverOverlaps() async {
        let taken = zip(Gen.int(in: 1...30), Gen.int(in: 0...6)).array(of: 0...2)
        await propertyCheck(input: taken, Gen.int(in: 1...30), Gen.int(in: 0...10), Gen.int(in: 1...40)) { taken, seen, length, count in
            var f = course()
            let m = matchings(f)
            // The classes before and after, kept clear of each other as the rule keeps them.
            var placed: [ClosedRange<Int>] = []
            for (i, (first, len)) in taken.enumerated() where !placed.contains(where: { $0.overlaps(first...(first + len)) }) {
                placed.append(first...(first + len))
                f.linkMaterial(m, session: f.sessions[i == 0 ? 0 : 2].id, firstPage: first, lastPage: first + len)
            }
            let viewed = [SessionMaterial(materialId: m, firstPage: seen, lastPage: seen + length)]
            for s in f.suggestedProgress(for: f.sessions[1], viewed: viewed, pageCounts: [m: count]) {
                guard let pages = s.pages else { continue }
                #expect(!f.pagesTaken(in: m, besides: f.sessions[1].id).contains { $0.overlaps(pages) })
                #expect(pages.upperBound <= count)
            }
        }
    }

    @Test func pagesAlreadySavedStay() {
        var f = course()
        let (m, other) = (matchings(f), flows(f))
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 12)
        f.linkMaterial(m, session: f.sessions[1].id, firstPage: 14, lastPage: 16)
        f.linkMaterial(other, session: f.sessions[1].id)
        let viewed = [SessionMaterial(materialId: m, firstPage: 13, lastPage: 22), SessionMaterial(materialId: other, firstPage: 2, lastPage: 5)]
        // Saved files first, in their order; an unranged link is filled like a new one.
        #expect(f.suggestedProgress(for: f.sessions[1], viewed: viewed) == [
            SessionMaterial(materialId: m, firstPage: 14, lastPage: 16),
            SessionMaterial(materialId: other, firstPage: 1, lastPage: 5),
        ])
    }

    @Test func withoutARecordingTheLastFileContinues() {
        var f = course()
        let (m, next) = (matchings(f), flows(f))
        #expect(f.suggestedProgress(for: f.sessions[0], viewed: []).isEmpty)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 12)
        #expect(f.suggestedProgress(for: f.sessions[1], viewed: []) == [SessionMaterial(materialId: m, firstPage: 13, lastPage: nil)])
        // A cancelled class in between changes nothing.
        f.sessions[1].isCancelled = true
        #expect(f.suggestedProgress(for: f.sessions[2], viewed: [], pageCounts: [m: 30]) == [SessionMaterial(materialId: m, firstPage: 13, lastPage: nil)])
        // Once the count says it is done, the next lecture file by name: 05_ before 06_, whatever order they were added in.
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 30)
        #expect(f.suggestedProgress(for: f.sessions[2], viewed: [], pageCounts: [m: 30]) == [SessionMaterial(materialId: next, firstPage: 1, lastPage: nil)])
        // The last lecture file done leaves nothing to suggest.
        f.linkMaterial(next, session: f.sessions[1].id, firstPage: 1, lastPage: 8)
        f.sessions[1].isCancelled = false
        #expect(f.suggestedProgress(for: f.sessions[2], viewed: [], pageCounts: [m: 30, next: 8]).isEmpty)
    }

    @Test func pagesStayWithinTheCount() {
        var f = course()
        let m = matchings(f)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 30)
        #expect(f.suggestedProgress(for: f.sessions[1], viewed: [SessionMaterial(materialId: m, firstPage: 28, lastPage: 50)], pageCounts: [m: 40])
            == [SessionMaterial(materialId: m, firstPage: 31, lastPage: 40)])
        // The file the last class finished leaves nothing new.
        #expect(f.suggestedProgress(for: f.sessions[1], viewed: [SessionMaterial(materialId: m, firstPage: 30, lastPage: 30)], pageCounts: [m: 30])
            == [SessionMaterial(materialId: m)])
    }

    // MARK: Replay

    // MARK: A link added by hand, and a prompt opened again

    @Test func aNewLinkStartsAfterTheLastClassOrStaysWholeFile() {
        var f = course()
        let m = matchings(f)
        #expect(f.suggestedLink(of: m, for: f.sessions[1], pageCount: nil) == SessionMaterial(materialId: m))
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 12)
        #expect(f.suggestedLink(of: m, for: f.sessions[1], pageCount: nil) == SessionMaterial(materialId: m, firstPage: 13))
        // A finished file has no page left for the next class.
        #expect(f.suggestedLink(of: m, for: f.sessions[1], pageCount: 12) == SessionMaterial(materialId: m))
    }

    /// The prompt was dismissed: nothing was saved, so opening it again starts after the last class, not at the first
    /// page the recording saw.
    @Test func aPromptOpenedAgainStartsFromTheRecording() {
        var f = course()
        let m = matchings(f)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 6)
        let session = f.sessions[1]
        f.recordings = [
            Recording(device: device, at: now, sessionId: session.id, file: "Recordings/a.m4a", duration: 600,
                      pages: [PageVisit(at: 0, materialId: m, page: 6), PageVisit(at: 100, materialId: m, page: 9)]),
            Recording(device: device, at: now, sessionId: session.id, file: "Recordings/b.m4a", duration: 600,
                      pages: [PageVisit(at: 0, materialId: m, page: 10), PageVisit(at: 100, materialId: m, page: 11)]),
            Recording(device: device, at: now, sessionId: f.sessions[2].id, file: "Recordings/c.m4a", duration: 600,
                      pages: [PageVisit(at: 0, materialId: m, page: 30)]),
        ]
        #expect(f.viewedPages(of: session) == [SessionMaterial(materialId: m, firstPage: 6, lastPage: 11)])
        #expect(f.suggestedProgress(for: session, viewed: f.viewedPages(of: session)) == [SessionMaterial(materialId: m, firstPage: 7, lastPage: 11)])
        #expect(f.suggestedLink(of: m, for: session, pageCount: nil) == SessionMaterial(materialId: m, firstPage: 7, lastPage: 11))
    }

    /// The recording was stopped and restarted in one class. The prompt the second stop raises sees both recordings,
    /// as a prompt opened again later will, though the one just stopped isn't saved yet.
    @Test func thePromptAtStopSeesTheClassesEarlierRecordingsToo() {
        var f = course()
        let m = matchings(f)
        let session = f.sessions[1]
        let first = Recording(device: device, at: now, sessionId: session.id, file: "Recordings/a.m4a", duration: 600,
                              pages: [PageVisit(at: 0, materialId: m, page: 6), PageVisit(at: 100, materialId: m, page: 9)])
        let second = Recording(device: device, at: now, sessionId: session.id, file: "Recordings/b.m4a", duration: 600,
                               pages: [PageVisit(at: 0, materialId: m, page: 10), PageVisit(at: 100, materialId: m, page: 11)])
        f.recordings = [first]
        let atStop = f.viewedPages(of: session, including: second)
        #expect(atStop == [SessionMaterial(materialId: m, firstPage: 6, lastPage: 11)])
        f.recordings = [first, second]
        #expect(f.viewedPages(of: session) == atStop)
        #expect(f.viewedPages(of: session, including: second) == atStop)
    }

    @Test func movingOneEndPushesTheOther() {
        let range = PageRange(first: 5, last: 9)
        #expect(range.moving(.first, to: 12, pages: nil) == PageRange(first: 12, last: 12))
        #expect(range.moving(.last, to: 3, pages: nil) == PageRange(first: 3, last: 3))
        // Up to the other end exactly: one page, from either side.
        #expect(range.moving(.first, to: 9, pages: 20) == PageRange(first: 9, last: 9))
        #expect(range.moving(.last, to: 5, pages: 20) == PageRange(first: 5, last: 5))
        #expect(range.moving(.first, to: 0, pages: 20).first == 1)
        #expect(range.moving(.last, to: 40, pages: 20).last == 20)
        // Pushed to the end of the file, the other end stops there too.
        #expect(range.moving(.first, to: 40, pages: 20) == PageRange(first: 20, last: 20))
        #expect(range.moving(.first, to: nil, pages: 20) == PageRange(first: nil, last: 9))
        #expect(PageRange().moving(.last, to: 4, pages: 20) == PageRange(first: nil, last: 4))
        // A count learned later brings the other end in.
        #expect(PageRange(first: 2, last: 30).moving(.first, to: 3, pages: 20) == PageRange(first: 3, last: 20))
        #expect(PageRange.bounds(20) == 1...20 && PageRange.bounds(0) == 1...1)
    }

    @Test func aTapFillsAMissingEndThenMovesTheNearerOne() {
        #expect(PageRange().tapping(8, pages: 20) == PageRange(first: 8, last: 8))
        #expect(PageRange(first: 7).tapping(11, pages: 20) == PageRange(first: 7, last: 11))
        #expect(PageRange(first: 7).tapping(3, pages: 20) == PageRange(first: 3, last: 7))
        #expect(PageRange(last: 11).tapping(4, pages: 20) == PageRange(first: 4, last: 11))
        #expect(PageRange(last: 11).tapping(15, pages: 20) == PageRange(first: 11, last: 15))
        let range = PageRange(first: 7, last: 11)
        #expect(range.tapping(5, pages: 20) == PageRange(first: 5, last: 11))
        #expect(range.tapping(14, pages: 20) == PageRange(first: 7, last: 14))
        // A tie goes to the start.
        #expect(range.tapping(9, pages: 20) == PageRange(first: 9, last: 11))
        #expect(range.tapping(40, pages: 20) == PageRange(first: 7, last: 20))
    }

    @Test func aLoneEndOpensTheRangeEitherWay() {
        let start = PageRange(first: 7)
        #expect(start.lone == .first && PageRange(last: 3).lone == .last)
        #expect(PageRange().lone == nil && PageRange(first: 1, last: 2).lone == nil)
        #expect(start.tapping(7, pages: 20) == PageRange(first: 7, last: 7))
        #expect(start.tapping(8, pages: 20) == PageRange(first: 7, last: 8))
        #expect(start.tapping(6, pages: 20) == PageRange(first: 6, last: 7))
        #expect(start.tapping(40, pages: 20).lone == nil)
    }

    @Test func aShiftKeepsTheLengthAndStopsAtTheEnds() {
        let range = PageRange(first: 7, last: 11)
        #expect(range.shifted(by: 3, pages: 20) == PageRange(first: 10, last: 14))
        #expect(range.shifted(by: -10, pages: 20) == PageRange(first: 1, last: 5))
        #expect(range.shifted(by: 30, pages: 20) == PageRange(first: 16, last: 20))
        #expect(PageRange(first: 7).shifted(by: 3, pages: 20) == PageRange(first: 7))
        // Longer than the file: it fills the file.
        #expect(PageRange(first: 1, last: 30).shifted(by: 2, pages: 20) == PageRange(first: 1, last: 20))
    }

    /// Any run of taps and shifts keeps the range inside the file and in order, and a tap always leaves both ends set.
    @Test func tapsAndShiftsKeepTheRangeInTheFile() async {
        let step = zip(Gen.int(in: 0...1), Gen.int(in: -30...60)).array(of: 1...12)
        await propertyCheck(input: step, Gen.int(in: 1...40)) { steps, pages in
            var range = PageRange()
            for (kind, n) in steps {
                let before = range
                range = kind == 0 ? range.tapping(n, pages: pages) : range.shifted(by: n, pages: pages)
                if kind == 0 { #expect(range.first != nil && range.last != nil) }
                if kind == 1, let f = before.first, let l = before.last { #expect(range.last! - range.first! == min(l - f, pages - 1)) }
                for p in [range.first, range.last].compactMap({ $0 }) { #expect((1...pages).contains(p)) }
                if let a = range.first, let b = range.last { #expect(a <= b) }
            }
        }
    }

    @Test func anEndTouchesABoundOrTheOtherEnd() {
        #expect(PageRange(first: 1, last: 9).touches(.first, pages: 20))
        #expect(PageRange(first: 4, last: 20).touches(.last, pages: 20))
        #expect(PageRange(first: 7, last: 7).touches(.first, pages: 20) && PageRange(first: 7, last: 7).touches(.last, pages: 20))
        #expect(!PageRange(first: 4, last: 9).touches(.first, pages: 20))
        // Without a count there is no top to hit.
        #expect(!PageRange(first: 4, last: 500).touches(.last, pages: nil))
        #expect(!PageRange(first: nil, last: 9).touches(.first, pages: 20))
    }

    /// Any run of moves, typed or dragged, emptied or past the file: every page set is within 1…pages and the start
    /// is never after the end. A page moved to inside the file is where that end lands.
    @Test func boundsHoldForAnyRunOfMoves() async {
        // -6 empties the field; the rest run past both ends of the file.
        let move = zip(Gen.int(in: 0...1), Gen.int(in: -6...60)).array(of: 1...12)
        await propertyCheck(input: move, Gen.int(in: 1...40)) { moves, pages in
            var range = PageRange()
            for (side, raw) in moves {
                let end: PageRange.End = side == 0 ? .first : .last
                let page = raw == -6 ? nil : raw
                range = range.moving(end, to: page, pages: pages)
                for p in [range.first, range.last].compactMap({ $0 }) { #expect((1...pages).contains(p)) }
                if let a = range.first, let b = range.last { #expect(a <= b) }
                if let page, (1...pages).contains(page) { #expect(range[end] == page) }
                if page == nil { #expect(range[end] == nil) }
            }
        }
    }

    @Test func anEndStopsAtAnotherClassesPages() {
        let taken = [1...4, 12...15]
        let range = PageRange(first: 6, last: 9)
        #expect(range.moving(.last, to: 13, pages: 20, besides: taken) == PageRange(first: 6, last: 11))
        #expect(range.moving(.first, to: 2, pages: 20, besides: taken) == PageRange(first: 5, last: 9))
        // Pushing the other end stops at the wall too.
        #expect(range.moving(.first, to: 14, pages: 20, besides: taken) == PageRange(first: 11, last: 11))
        #expect(range.shifted(by: 6, pages: 20, besides: taken) == PageRange(first: 8, last: 11))
        #expect(range.tapping(18, pages: 20, besides: taken) == PageRange(first: 6, last: 11))
        // A first tap on a taken page sets nothing; beside it, it starts there.
        #expect(PageRange().tapping(13, pages: 20, besides: taken) == PageRange())
        #expect(PageRange().tapping(16, pages: 20, besides: taken) == PageRange(first: 16, last: 16))
        // At a wall the end touches, for the firmer tick.
        #expect(PageRange(first: 5, last: 11).touches(.first, pages: nil, besides: taken))
        #expect(PageRange(first: 5, last: 11).touches(.last, pages: nil, besides: taken))
        #expect(!PageRange(first: 6, last: 10).touches(.last, pages: nil, besides: taken))
        #expect(PageRange.room(at: 13, besides: taken, pages: 20) == nil && PageRange.room(at: 8, besides: taken, pages: 20) == 5...11)
    }

    @Test func aRangeIsFittedClearOfOtherClasses() {
        let taken = [1...4, 12...15]
        #expect(PageRange(first: 3, last: 13).fitted(besides: taken, pages: 20) == PageRange(first: 5, last: 11))
        #expect(PageRange(first: 13, last: 18).fitted(besides: taken, pages: 20) == PageRange(first: 16, last: 18))
        #expect(PageRange(first: 13).fitted(besides: taken, pages: 20) == PageRange(first: 16))
        #expect(PageRange(first: 2, last: 4).fitted(besides: taken, pages: 20) == PageRange())
        #expect(PageRange(first: 13, last: 15).fitted(besides: [1...15], pages: 15) == PageRange())
    }

    /// Starting clear of the other classes, any run of moves, taps and shifts stays clear of them, in the file and in order.
    @Test func movesNeverEnterAnotherClassesPages() async {
        let step = zip(Gen.int(in: 0...3), Gen.int(in: -10...50)).array(of: 1...12)
        let walls = zip(Gen.int(in: 1...40), Gen.int(in: 0...5)).array(of: 0...3)
        await propertyCheck(input: step, walls, Gen.int(in: 1...40)) { steps, walls, pages in
            var taken: [ClosedRange<Int>] = []
            for (a, n) in walls where !taken.contains(where: { $0.overlaps(a...(a + n)) }) { taken.append(a...(a + n)) }
            var range = PageRange()
            for (kind, n) in steps {
                switch kind {
                case 0: range = range.tapping(n, pages: pages, besides: taken)
                case 1: range = range.shifted(by: n, pages: pages, besides: taken)
                case 2: range = range.moving(.first, to: n, pages: pages, besides: taken)
                default: range = range.moving(.last, to: n, pages: pages, besides: taken)
                }
                for p in [range.first, range.last].compactMap({ $0 }) {
                    #expect((1...pages).contains(p))
                    #expect(!taken.contains { $0.contains(p) })
                }
                if let a = range.first, let b = range.last {
                    #expect(a <= b)
                    #expect(!taken.contains { $0.overlaps(a...b) })
                }
            }
        }
    }

    @Test func theLineShowsThePageOnScreenWhenItStarted() {
        let m = UUID()
        let r = Recording(device: device, at: now, sessionId: nil, file: "Recordings/a.m4a", duration: 300, pages: [
            PageVisit(at: 10, materialId: m, page: 3), PageVisit(at: 12, materialId: m, page: 4), PageVisit(at: 100, materialId: m, page: nil),
        ])
        #expect(r.visit(at: 5) == nil)
        #expect(r.visit(at: 11)?.page == 3)
        #expect(r.visit(at: 12)?.page == 4)
        #expect(r.visit(at: 150) == nil)
    }
}
