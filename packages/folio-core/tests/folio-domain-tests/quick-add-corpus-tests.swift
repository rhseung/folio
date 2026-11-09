import FolioDomain
import Foundation
import PropertyBased
import Testing

/// Lines as they get typed into the quick-add field, each with what it should save. The clock is Thursday
/// 2026-10-22 15:00, so `금` is tomorrow and `다음 주 수요일` is 10/28.
struct QuickAddCorpusTests {
    let device = UUID()
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        c.locale = Locale(identifier: "ko_KR")
        return c
    }()

    let codes: [CourseCode]
    let courses: [Course]

    init() {
        let device = device
        let prefixes = ["MA", "EC", "MC", "MM", "GS"]
        let made = prefixes.map { CourseCode(device: device, at: .now, prefix: $0) }
        codes = made
        func code(_ p: String) -> [UUID] { [made[prefixes.firstIndex(of: p)!].id] }
        courses = [
            Course(device: device, at: .now, title: "선형대수학과 응용", codes: code("MA"), number: "2004-02"),
            Course(device: device, at: .now, title: "그래프 이론", codes: code("EC"), number: "4207-01"),
            Course(device: device, at: .now, title: "컴퓨터네트워킹", codes: code("EC"), number: "3204"),
            Course(device: device, at: .now, title: "로봇공학", codes: code("MC"), number: "3101"),
            Course(device: device, at: .now, title: "확률과 통계", codes: code("MM"), number: "2001"),
            Course(device: device, at: .now, title: "운영체제", codes: code("EC"), number: "3205"),
            Course(device: device, at: .now, title: "일반물리학", codes: code("GS"), number: "1101"),
        ]
    }

    var now: Date { date("2026-10-22 15:00") }

    func date(_ text: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    struct Case: Sendable {
        let line: String
        /// Index into `courses`, nil when the line names none.
        let course: Int?
        let title: String
        /// `yyyy-MM-dd HH:mm`, nil when the line has no deadline.
        let due: String?
        var weekly = false
    }

    static let cases: [Case] = [
        // Course by alias, code and full name
        Case(line: "선대 HW5 금 23:59", course: 0, title: "HW5", due: "2026-10-23 23:59"),
        Case(line: "그래프 HW3 내일", course: 1, title: "HW3", due: "2026-10-23 23:59"),
        Case(line: "EC4207 SP2 월", course: 1, title: "SP2", due: "2026-10-26 23:59"),
        Case(line: "MA2004 HW7 내일", course: 0, title: "HW7", due: "2026-10-23 23:59"),
        Case(line: "ma2004 HW7 내일", course: 0, title: "HW7", due: "2026-10-23 23:59"),
        Case(line: "GS1101 HW2 금", course: 6, title: "HW2", due: "2026-10-23 23:59"),
        Case(line: "선형대수 HW7 내일", course: 0, title: "HW7", due: "2026-10-23 23:59"),
        Case(line: "선형대수학과 응용 HW7 내일", course: 0, title: "HW7", due: "2026-10-23 23:59"),
        Case(line: "그래프 이론 HW4 금", course: 1, title: "HW4", due: "2026-10-23 23:59"),
        Case(line: "확률과 통계 Lab1 화", course: 4, title: "Lab1", due: "2026-10-27 23:59"),
        Case(line: "운체 HW2 금", course: 5, title: "HW2", due: "2026-10-23 23:59"),
        Case(line: "일물 Report3 모레", course: 6, title: "Report3", due: "2026-10-24 23:59"),
        Case(line: "물리 HW2 금", course: 6, title: "HW2", due: "2026-10-23 23:59"),
        Case(line: "확통 HW3 11/2", course: 4, title: "HW3", due: "2026-11-02 23:59"),
        Case(line: "컴네에 Lab3 내일", course: 2, title: "Lab3", due: "2026-10-23 23:59"),
        Case(line: "내일 7시 컴퓨터네트워킹에다 Lab3", course: 2, title: "Lab3", due: "2026-10-23 19:00"),
        Case(line: "선대 HW5 내일 7:00", course: 0, title: "HW5", due: "2026-10-23 07:00"),
        Case(line: "선대 HW5 내일 새벽 2시", course: 0, title: "HW5", due: "2026-10-23 02:00"),
        Case(line: "HW4 금요일까지", course: nil, title: "HW4", due: "2026-10-23 23:59"),
        Case(line: "보고서 금", course: nil, title: "보고서", due: "2026-10-23 23:59"),
        // Kinds and numbers in the title
        Case(line: "운영체제 Project1 12/5", course: 5, title: "Project1", due: "2026-12-05 23:59"),
        Case(line: "그래프 Reading2 내일", course: 1, title: "Reading2", due: "2026-10-23 23:59"),
        Case(line: "선대 HW 5 금", course: 0, title: "HW 5", due: "2026-10-23 23:59"),
        Case(line: "그래프 SP 2 다음 주 월요일", course: 1, title: "SP 2", due: "2026-10-26 23:59"),
        Case(line: "그래프 HW 금 오후 11:59", course: 1, title: "HW", due: "2026-10-23 23:59"),
        Case(line: "확통 Lab 3 금까지 제출", course: 4, title: "Lab 3 제출", due: "2026-10-23 23:59"),
        // Week words
        Case(line: "컴네 Lab2 보고서 다음 주 수요일까지", course: 2, title: "Lab2 보고서", due: "2026-10-28 23:59"),
        Case(line: "선대 HW5 다음 주 금", course: 0, title: "HW5", due: "2026-10-30 23:59"),
        Case(line: "선대 HW5 다음주 금요일", course: 0, title: "HW5", due: "2026-10-30 23:59"),
        Case(line: "선대 HW5 이번 주 금", course: 0, title: "HW5", due: "2026-10-23 23:59"),
        Case(line: "선대 HW5 이번주 토요일", course: 0, title: "HW5", due: "2026-10-24 23:59"),
        Case(line: "그래프 HW3 다음 주 수 오후 6시", course: 1, title: "HW3", due: "2026-10-28 18:00"),
        Case(line: "선대 HW5 담주 월", course: 0, title: "HW5", due: "2026-10-26 23:59"),
        // Days
        Case(line: "선대 HW5 오늘", course: 0, title: "HW5", due: "2026-10-22 23:59"),
        Case(line: "선대 HW5 오늘 18:00", course: 0, title: "HW5", due: "2026-10-22 18:00"),
        Case(line: "선대 HW5 23:59", course: 0, title: "HW5", due: "2026-10-22 23:59"),
        Case(line: "선대 HW5 11월 3일", course: 0, title: "HW5", due: "2026-11-03 23:59"),
        Case(line: "선대 HW5 11월 3일 오후 2시", course: 0, title: "HW5", due: "2026-11-03 14:00"),
        Case(line: "선대 HW5 11.3", course: 0, title: "HW5", due: "2026-11-03 23:59"),
        Case(line: "선대 HW6 10/30 23:59까지", course: 0, title: "HW6", due: "2026-10-30 23:59"),
        Case(line: "선대 HW5 10월 30일까지", course: 0, title: "HW5", due: "2026-10-30 23:59"),
        Case(line: "선대 HW5 30일", course: 0, title: "HW5", due: "2026-10-30 23:59"),
        Case(line: "확통 HW3 3/2", course: 4, title: "HW3", due: "2027-03-02 23:59"),
        Case(line: "선대 일요일까지 HW", course: 0, title: "HW", due: "2026-10-25 23:59"),
        Case(line: "선대 토론 준비 목", course: 0, title: "토론 준비", due: "2026-10-22 23:59"),
        // Times
        Case(line: "확통 HW2 11/20 오후 3시", course: 4, title: "HW2", due: "2026-11-20 15:00"),
        Case(line: "선대 HW5 금 오후 11시", course: 0, title: "HW5", due: "2026-10-23 23:00"),
        Case(line: "선대 HW5 금 밤 11시", course: 0, title: "HW5", due: "2026-10-23 23:00"),
        Case(line: "선대 HW5 금 오전 9시", course: 0, title: "HW5", due: "2026-10-23 09:00"),
        Case(line: "선대 HW5 금 오후 3시 30분", course: 0, title: "HW5", due: "2026-10-23 15:30"),
        Case(line: "선대 HW5 금 오후 3시반", course: 0, title: "HW5", due: "2026-10-23 15:30"),
        Case(line: "선대 HW5 금 23시 59분", course: 0, title: "HW5", due: "2026-10-23 23:59"),
        Case(line: "선대 HW5 금 정오", course: 0, title: "HW5", due: "2026-10-23 12:00"),
        Case(line: "그래프 Reading2 내일 자정", course: 1, title: "Reading2", due: "2026-10-24 00:00"),
        Case(line: "선대 HW5 금요일 자정", course: 0, title: "HW5", due: "2026-10-24 00:00"),
        Case(line: "그래프 HW3 일요일 밤 12시", course: 1, title: "HW3", due: "2026-10-26 00:00"),
        Case(line: "컴네 HW1 금 마감", course: 2, title: "HW1", due: "2026-10-23 23:59"),
        // Weekly
        Case(line: "로봇 실습 보고서 매주 화", course: 3, title: "실습 보고서", due: "2026-10-27 23:59", weekly: true),
        Case(line: "선대 매주 금 퀴즈", course: 0, title: "퀴즈", due: "2026-10-23 23:59", weekly: true),
        Case(line: "로봇 매주 화요일 실습 보고서", course: 3, title: "실습 보고서", due: "2026-10-27 23:59", weekly: true),
        // Numbers and day-like words that belong to the title
        Case(line: "선대 3장 풀기 금", course: 0, title: "3장 풀기", due: "2026-10-23 23:59"),
        Case(line: "선대 2장 연습문제 1-10번 금", course: 0, title: "2장 연습문제 1-10번", due: "2026-10-23 23:59"),
        Case(line: "선대 3.2절 읽기 금", course: 0, title: "3.2절 읽기", due: "2026-10-23 23:59"),
        Case(line: "선대 p.32 풀기 금", course: 0, title: "p.32 풀기", due: "2026-10-23 23:59"),
        Case(line: "그래프 2주차 복습 금", course: 1, title: "2주차 복습", due: "2026-10-23 23:59"),
        Case(line: "선대 월말 정리", course: 0, title: "월말 정리", due: nil),
        Case(line: "선대 금속 실험 보고서 화", course: 0, title: "금속 실험 보고서", due: "2026-10-27 23:59"),
        Case(line: "선대 퀴즈 준비 금", course: 0, title: "퀴즈 준비", due: "2026-10-23 23:59"),
        Case(line: "선대 중간고사 공부 11/5", course: 0, title: "중간고사 공부", due: "2026-11-05 23:59"),
        Case(line: "선대 HW5", course: 0, title: "HW5", due: nil),
        Case(line: "선대 2시간 복습", course: 0, title: "2시간 복습", due: nil),
        Case(line: "선대 고유값 3문제 풀기 금", course: 0, title: "고유값 3문제 풀기", due: "2026-10-23 23:59"),
        Case(line: "Lab3 보고서 초안과 실험 데이터 정리, 그래프와 오차 분석 포함해서 다음 주 수요일까지", course: nil,
             title: "Lab3 보고서 초안과 실험 데이터 정리, 그래프와 오차 분석 포함해서", due: "2026-10-28 23:59"),
    ]

    func check(_ c: Case) -> String? {
        let r = QuickAdd.parse(c.line, courses: courses, codes: codes, now: now, calendar: calendar)
        var wrong: [String] = []
        let course = r.courseId.flatMap { id in courses.firstIndex { $0.id == id } }
        if course != c.course { wrong.append("course \(course.map { courses[$0].title } ?? "-")") }
        if r.title != c.title { wrong.append("title \"\(r.title)\"") }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let due = r.due.map(f.string)
        if due != c.due { wrong.append("due \(due ?? "-")") }
        if (r.repeats == .weekly) != c.weekly { wrong.append("weekly \(r.repeats == .weekly)") }
        return wrong.isEmpty ? nil : "\(c.line) → " + wrong.joined(separator: ", ")
    }

    /// Any course, title words and deadline put together: the course and deadline come out whole wherever the deadline
    /// sits, and the title is the title words in order with nothing of the deadline left in it.
    @Test func coursesTitlesAndDeadlinesComeApartInAnyOrder() async {
        let aliases: [(String, Int)] = [("선대", 0), ("그래프 이론", 1), ("컴네", 2), ("확률과 통계", 4), ("EC4207", 1), ("운체", 5)]
        let titles = ["보고서", "HW3", "정리", "Lab2", "실험", "3장", "읽기", "1-10번", "p.32", "초안"]
        let dues: [(String, String)] = [
            ("금", "2026-10-23 23:59"), ("다음 주 수요일까지", "2026-10-28 23:59"), ("11/20 오후 3시", "2026-11-20 15:00"),
            ("내일 자정", "2026-10-24 00:00"), ("금 마감", "2026-10-23 23:59"), ("이번주 토요일", "2026-10-24 23:59"),
            ("11월 3일 오전 9시", "2026-11-03 09:00"), ("모레 23:59", "2026-10-24 23:59"), ("담주 월 밤 11시", "2026-10-26 23:00"),
        ]
        let input = zip(Gen.int(in: 0...(aliases.count - 1)), Gen.int(in: 0...(titles.count - 1)).array(of: 1...4),
                        zip(Gen.int(in: 0...(dues.count - 1)), Gen.int(in: 0...4)))
        await propertyCheck(input: input) { course, picked, due in
            let words = picked.map { titles[$0] }
            var line = words
            line.insert(dues[due.0].0, at: min(due.1, line.count))
            let text = ([aliases[course].0] + line).joined(separator: " ")
            let r = QuickAdd.parse(text, courses: courses, codes: codes, now: now, calendar: calendar)
            #expect(r.courseId == courses[aliases[course].1].id, "\(text)")
            #expect(r.title == words.joined(separator: " "), "\(text)")
            #expect(r.due == date(dues[due.0].1), "\(text)")
        }
    }

    func read(_ line: String) -> QuickAdd { QuickAdd.parse(line, courses: courses, codes: codes, now: now, calendar: calendar) }

    @Test func theLineMarksItsCourseAndKind() {
        let line = "그래프 이론 Lab 3 보고서 금"
        let r = read(line)
        #expect(r.courseRanges.map { String(line[$0]) } == ["그래프 이론"])
        #expect(r.kind == .lab && r.number == 3 && r.folderName == "Lab03")
        #expect(r.kindRange.map { String(line[$0]) } == "Lab 3")
        #expect(QuickAdd.renumbered(line, at: r.kindRange!, kind: .homework, number: 4) == "그래프 이론 HW4 보고서 금")
        // A number inside the deadline or the course is not the assignment's.
        #expect(read("확통 보고서 11/20").kind == nil)
    }

    /// A chip's pick holds while more of the title is typed, and gives way once the line reads that field anew.
    @Test func aPickHoldsUntilTheLineReadsItsFieldAgain() {
        var picks = QuickAddPicks()
        let first = read("HW5 금")
        picks.pickCourse(courses[3].id, over: first)
        picks.pickDue(date("2026-10-30 12:00"), over: first)
        let more = read("HW5 보고서 금")
        picks.keep(over: more)
        #expect(picks.applied(to: more).courseId == courses[3].id)
        #expect(picks.applied(to: more).due == date("2026-10-30 12:00"))
        let named = read("선대 HW5 보고서 금")
        picks.keep(over: named)
        #expect(picks.applied(to: named).courseId == courses[0].id)
        #expect(picks.applied(to: named).due == date("2026-10-30 12:00"))
        let redated = read("선대 HW5 보고서 월")
        picks.keep(over: redated)
        #expect(picks.isEmpty && picks.applied(to: redated).due == date("2026-10-26 23:59"))
    }

    @Test func readsTheCorpus() {
        let failures = Self.cases.compactMap(check)
        print("quick-add corpus: \(Self.cases.count - failures.count)/\(Self.cases.count) read right")
        for failure in failures { Issue.record(Comment(rawValue: failure)) }
    }
}
