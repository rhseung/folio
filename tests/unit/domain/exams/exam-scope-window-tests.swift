import FolioDomain
import Foundation
import PropertyBased
import Testing

struct ExamScopeWindowTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_793_149_200)
    let day: TimeInterval = 86_400

    // 렉처 하나(쪽 1~40)를 10쪽씩 단원 넷으로 나누고, 매주 수업 여덟 번 중 넷째 주 뒤에 중간고사, 여덟째 주 뒤에
    // 기말고사가 있다.
    func course() -> CourseFile {
        var f = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        f.materials = [Material(device: device, at: now, path: "Lectures/05_Matchings.pdf", role: .lecture, status: .classified)]
        f.units = (0..<4).map { i in
            var u = Unit(device: device, at: now, title: "단원 \(i + 1)", order: i + 1)
            u.lecturePages = [UnitPages(materialId: f.materials[0].id, firstPage: i * 10 + 1, lastPage: i * 10 + 10)]
            return u
        }
        f.sessions = (0..<8).map { Session(device: device, at: now, week: $0 + 1, date: at(week: $0)) }
        f.exams = [
            Exam(device: device, at: now, title: "중간고사", start: at(week: 3) + 3 * day),
            Exam(device: device, at: now, title: "기말고사", start: at(week: 7) + 3 * day),
        ]
        return f
    }

    func at(week: Int) -> Date { now + Double(week) * 7 * day }
    var lecture: (CourseFile) -> UUID { { $0.materials[0].id } }
    func ids(_ f: CourseFile, _ i: [Int]) -> [UUID] { i.map { f.units[$0].id } }

    @Test func theFinalCoversOnlyWhatCameAfterTheMidterm() {
        var f = course()
        f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: 1, lastPage: 12)
        f.linkMaterial(lecture(f), session: f.sessions[3].id, firstPage: 13, lastPage: 25)
        f.linkMaterial(lecture(f), session: f.sessions[6].id, firstPage: 26, lastPage: 40)
        #expect(f.computedScope(of: f.exams[0]) == ids(f, [0, 1, 2]))
        // 단원 3은 중간고사 전에 시작해 뒤에도 이어 배웠으므로 두 시험에 모두 든다.
        #expect(f.computedScope(of: f.exams[1]) == ids(f, [2, 3]))
    }

    @Test func classesWithoutPagesBeforeTheLastPageCountAsTaught() {
        var f = course()
        // 넷째 주에만 진도 쪽이 있다. 그 앞 회차들은 비었어도 1~20쪽을 배운 것이다.
        f.linkMaterial(lecture(f), session: f.sessions[3].id, firstPage: 15, lastPage: 20)
        #expect(f.computedScope(of: f.exams[0]) == ids(f, [0, 1]))
        #expect(f.reach(of: lecture(f), before: f.exams[0].start) == LectureReach(page: 20, explicit: true))
        #expect(f.isTaught(f.units[0], before: f.exams[0].start) && !f.isTaught(f.units[2], before: f.exams[0].start))
    }

    @Test func aLectureWithoutPagesIsTaughtUpToItsSessionsUnits() {
        var f = course()
        f.linkMaterial(lecture(f), session: f.sessions[0].id)
        f.toggle(session: f.sessions[0].id, unit: f.units[1].id)
        #expect(f.reach(of: lecture(f), before: f.exams[0].start) == LectureReach(page: 20, explicit: false))
        #expect(f.computedScope(of: f.exams[0]) == ids(f, [0, 1]))

        var bare = course()
        bare.linkMaterial(lecture(bare), session: bare.sessions[0].id)
        #expect(bare.reach(of: lecture(bare), before: bare.exams[0].start) == .whole)
        #expect(bare.computedScope(of: bare.exams[0]) == ids(bare, [0, 1, 2, 3]))
    }

    @Test func aGuessBeforeTheMidtermGivesWayToPagesAfterIt() {
        var f = course()
        // 중간고사 전에는 진도 쪽 없이 렉처만 이었으므로 렉처 전체로 짐작하지만, 그 뒤 수업이 21쪽에서 시작하므로
        // 20쪽까지만 배운 것으로 본다.
        f.linkMaterial(lecture(f), session: f.sessions[0].id)
        f.linkMaterial(lecture(f), session: f.sessions[5].id, firstPage: 21, lastPage: 32)
        #expect(f.computedScope(of: f.exams[1]) == ids(f, [2, 3]))
    }

    @Test func parentsOfScopedUnitsComeAlong() {
        var f = course()
        var chapter = Unit(device: device, at: now, title: "장", order: 9)
        chapter.lecturePages = []
        f.units.append(chapter)
        f.units[0].parentId = chapter.id
        f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: 1, lastPage: 8)
        #expect(f.computedScope(of: f.exams[0]) == [chapter.id, f.units[0].id])
    }

    @Test func anExamWithoutADateHasNoComputedScope() {
        var f = course()
        f.exams[0].start = nil
        f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: 1, lastPage: 12)
        #expect(f.computedScope(of: f.exams[0]) == nil)
        f.setScope(ids(f, [0]), exam: f.exams[0].id)
        #expect(f.scope(of: f.exams[0]) == ids(f, [0]) && f.exams[0].addedScopeUnitIds == ids(f, [0]))
    }

    @Test func anEditedScopeStillTakesNewlyTaughtUnits() {
        var f = course()
        f.linkMaterial(lecture(f), session: f.sessions[4].id, firstPage: 21, lastPage: 28)
        f.toggle(exam: f.exams[1].id, unit: f.units[2].id)
        f.addScope(ids(f, [0]), exam: f.exams[1].id)
        #expect(f.exams[1].removedScopeUnitIds == ids(f, [2]) && f.exams[1].addedScopeUnitIds == ids(f, [0]))
        f.linkMaterial(lecture(f), session: f.sessions[6].id, firstPage: 29, lastPage: 40)
        #expect(f.scope(of: f.exams[1]) == ids(f, [0, 3]))
        #expect(f.isEdited(scopeOf: f.exams[1]))
        f.resetScope(exam: f.exams[1].id)
        #expect(f.scope(of: f.exams[1]) == ids(f, [2, 3]) && !f.isEdited(scopeOf: f.exams[1]))
    }

    // 같은 성적 항목에 이은 퀴즈들을 날짜(주 단위 오프셋)마다 더한다.
    func addQuizzes(_ f: inout CourseFile, at days: [Double]) -> [Exam] {
        let component = UUID()
        let quizzes = days.enumerated().map { i, d in
            var q = Exam(device: device, at: now, title: "Quiz\(i + 1)", start: now + d * day)
            q.componentId = component
            return q
        }
        f.exams += quizzes
        return quizzes
    }

    @Test func aQuizRightBeforeTheFinalLeavesItsScopeAlone() {
        var f = course()
        f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: 1, lastPage: 12)
        f.linkMaterial(lecture(f), session: f.sessions[3].id, firstPage: 13, lastPage: 25)
        f.linkMaterial(lecture(f), session: f.sessions[6].id, firstPage: 26, lastPage: 40)
        // 둘째 퀴즈는 기말 이틀 전이다. 퀴즈가 기말 범위를 끊으면 기말에는 퀴즈 뒤의 수업만 남는다.
        let quizzes = addQuizzes(&f, at: [36, 50])
        #expect(f.previousExam(before: f.exams[1])?.id == f.exams[0].id)
        #expect(f.computedScope(of: f.exams[1]) == ids(f, [2, 3]))
        // 퀴즈끼리는 서로 끊는다. 둘째 퀴즈는 첫 퀴즈(36일) 뒤의 수업, 26~40쪽이다.
        #expect(f.previousExam(before: quizzes[1])?.id == quizzes[0].id)
        #expect(f.computedScope(of: quizzes[1]) == ids(f, [2, 3]))
    }

    @Test func aQuizAfterTheMidtermCountsFromTheMidterm() {
        var f = course()
        f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: 1, lastPage: 12)
        f.linkMaterial(lecture(f), session: f.sessions[3].id, firstPage: 13, lastPage: 25)
        f.linkMaterial(lecture(f), session: f.sessions[4].id, firstPage: 26, lastPage: 30)
        // 중간고사(24일)가 첫 퀴즈(8일)보다 뒤라서 둘째 퀴즈(36일)는 중간고사 뒤의 26~30쪽, 단원 3만 센다.
        let quizzes = addQuizzes(&f, at: [8, 36])
        #expect(f.previousExam(before: quizzes[1])?.id == f.exams[0].id)
        #expect(f.computedScope(of: quizzes[1]) == ids(f, [2]))
    }

    @Test func anExamWithoutOthersOnItsComponentStillCutsTheWindow() {
        var f = course()
        f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: 1, lastPage: 12)
        f.linkMaterial(lecture(f), session: f.sessions[6].id, firstPage: 13, lastPage: 40)
        // 성적 항목에 시험이 하나뿐이면 큰 시험이다. 퀴즈를 성적 항목에 잇지 않은 과목은 지금처럼 끊는다.
        var lone = Exam(device: device, at: now, title: "Quiz", start: at(week: 6) + day)
        lone.componentId = UUID()
        f.exams.append(lone)
        #expect(f.previousExam(before: f.exams[1])?.id == lone.id)
    }

    @Test func quizzesNeverChangeTheMidtermOrFinalScope() async {
        await propertyCheck(input: Gen.int(in: 1...40), Gen.int(in: 1...40), Gen.int(in: 0...55).array(of: 2...5)) { a, b, days in
            var f = course()
            let (mid, end) = (min(a, b), max(a, b))
            f.linkMaterial(lecture(f), session: f.sessions[1].id, firstPage: 1, lastPage: mid)
            f.linkMaterial(lecture(f), session: f.sessions[5].id, firstPage: min(mid + 1, end), lastPage: end)
            let before = f.exams.map { f.computedScope(of: $0) }
            _ = addQuizzes(&f, at: days.map(Double.init))
            #expect(f.exams.prefix(2).map { f.computedScope(of: $0) } == before)
        }
    }

    @Test func scopesOfConsecutiveExamsCoverEverythingTaught() async {
        await propertyCheck(input: Gen.int(in: 1...40), Gen.int(in: 1...40)) { a, b in
            var f = course()
            let (mid, end) = (min(a, b), max(a, b))
            f.linkMaterial(lecture(f), session: f.sessions[1].id, firstPage: 1, lastPage: mid)
            f.linkMaterial(lecture(f), session: f.sessions[5].id, firstPage: min(mid + 1, end), lastPage: end)
            let both = Set((f.computedScope(of: f.exams[0]) ?? []) + (f.computedScope(of: f.exams[1]) ?? []))
            let taught = Set(f.units.filter { f.isTaught($0, before: f.exams[1].start) }.map(\.id))
            #expect(both == taught)
        }
    }
}
