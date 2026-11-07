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

    @Test func aRecapShowsThePagesGoneOver() {
        var f = course()
        let m = matchings(f)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 1, lastPage: 20)
        #expect(f.suggestedProgress(for: f.sessions[1], viewed: [SessionMaterial(materialId: m, firstPage: 15, lastPage: 18)])
            == [SessionMaterial(materialId: m, firstPage: 15, lastPage: 18)])
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
        #expect(f.suggestedProgress(for: f.sessions[1], viewed: [SessionMaterial(materialId: m, firstPage: 30, lastPage: 30)], pageCounts: [m: 30])
            == [SessionMaterial(materialId: m, firstPage: 30, lastPage: 30)])
    }

    // MARK: Replay

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
