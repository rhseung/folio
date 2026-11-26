import FolioDomain
import Foundation
import PropertyBased
import Testing

struct UnitGroupTests {
    let device = UUID()
    let start = Date(timeIntervalSince1970: 1_793_149_200)
    let day: TimeInterval = 86_400

    // 렉처 하나(쪽 1~60)를 10쪽씩 단원 여섯으로 나눈다. 매주 수업이 있고 넷째 주 뒤에 중간고사, 여덟째 주 뒤에
    // 기말고사가 있다. 지금은 여섯째 주다.
    func course() -> CourseFile {
        var f = CourseFile(course: Course(device: device, at: start, title: "선형대수학"))
        f.materials = [Material(device: device, at: start, path: "Lectures/01_Vectors.pdf", role: .lecture, status: .classified)]
        f.units = (0..<6).map { i in
            var u = Unit(device: device, at: start, title: "단원 \(i + 1)", order: i + 1)
            u.lecturePages = [UnitPages(materialId: f.materials[0].id, firstPage: i * 10 + 1, lastPage: i * 10 + 10)]
            return u
        }
        f.sessions = (0..<8).map { Session(device: device, at: start, week: $0 + 1, date: at(week: $0)) }
        f.exams = [
            Exam(device: device, at: start, title: "중간고사", start: at(week: 3) + 3 * day),
            Exam(device: device, at: start, title: "기말고사", start: at(week: 7) + 3 * day),
        ]
        f.linkMaterial(f.materials[0].id, session: f.sessions[0].id, firstPage: 1, lastPage: 20)
        f.linkMaterial(f.materials[0].id, session: f.sessions[4].id, firstPage: 21, lastPage: 30)
        return f
    }

    func at(week: Int) -> Date { start + Double(week) * 7 * day }
    var now: Date { at(week: 5) + day }
    func ids(_ f: CourseFile, _ i: [Int]) -> [UUID] { i.map { f.units[$0].id } }

    @Test func unitsOutsideTheFinalAreGroupedByPastExamThenTaughtThenUntaught() {
        var f = course()
        // 단원 2는 중간고사 범위에서 뺐지만 배웠다. 단원 4~6은 아직 안 배웠다.
        f.toggle(exam: f.exams[0].id, unit: f.units[1].id)
        let groups = f.unitGroups(besides: f.exams[1], now: now)
        #expect(f.scope(of: f.exams[1]) == ids(f, [2]))
        #expect(
            groups == [
                UnitGroup(kind: .exam(f.exams[0].id), unitIds: ids(f, [0])), UnitGroup(kind: .untested, unitIds: ids(f, [1])),
                UnitGroup(kind: .untaught, unitIds: ids(f, [3, 4, 5])),
            ])
    }

    @Test func aUnitInSeveralPastExamsGoesToTheLatest() {
        var f = course()
        let quiz = Exam(device: device, at: start, title: "Quiz1", start: at(week: 1) + day)
        f.exams.append(quiz)
        // 퀴즈 범위는 단원 1~2다. 중간고사 범위에 단원 1을 더하면 단원 1은 더 최근인 중간고사에만 든다.
        f.addScope(ids(f, [0]), exam: f.exams[0].id)
        let groups = f.unitGroups(besides: f.exams[1], now: now)
        #expect(groups.first == UnitGroup(kind: .exam(f.exams[0].id), unitIds: ids(f, [0])))
        #expect(groups.dropFirst().first == UnitGroup(kind: .exam(quiz.id), unitIds: ids(f, [1])))
    }

    @Test func aChapterWithATaughtSectionIsTaught() {
        var f = course()
        var chapter = Unit(device: device, at: start, title: "1장", order: 0)
        chapter.lecturePages = []
        f.units.append(chapter)
        f.units[2].parentId = chapter.id
        f.toggle(exam: f.exams[1].id, unit: chapter.id)
        // 장과 그 아래 단원 3을 기말 범위에서 뺐다. 단원 3을 배웠으므로 장도 배운 단원이다.
        let untested = f.unitGroups(besides: f.exams[1], now: now).first { $0.kind == .untested }
        #expect(untested?.unitIds == [chapter.id, f.units[2].id])
    }

    @Test func groupsSplitEveryUnitOutsideTheScopeOnce() async {
        await propertyCheck(input: Gen.int(in: 0...1).array(of: 6), Gen.int(in: 0...1).array(of: 6), Gen.int(in: 0...7)) { mid, fin, week in
            var f = course()
            for (i, flip) in mid.enumerated() where flip == 1 { f.toggle(exam: f.exams[0].id, unit: f.units[i].id) }
            for (i, flip) in fin.enumerated() where flip == 1 { f.toggle(exam: f.exams[1].id, unit: f.units[i].id) }
            let groups = f.unitGroups(besides: f.exams[1], now: at(week: week))
            let grouped = groups.flatMap(\.unitIds)
            let outside = Set(f.units.map(\.id)).subtracting(f.scope(of: f.exams[1]))
            #expect(grouped.count == Set(grouped).count && Set(grouped) == outside)
            for g in groups {
                guard case .exam(let id) = g.kind else { continue }
                let scope = f.exams.first { $0.id == id }.map { f.scope(of: $0) } ?? []
                #expect(Set(g.unitIds).isSubset(of: scope))
            }
        }
    }
}
