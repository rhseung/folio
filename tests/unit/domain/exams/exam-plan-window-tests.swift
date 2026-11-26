import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

struct ExamPlanWindowTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_793_149_200)
    let today = LocalDate(Date(timeIntervalSince1970: 1_793_149_200), in: Calendar(identifier: .gregorian))

    func exam(_ offsets: [Int]) -> Exam {
        var e = Exam(device: device, at: now, title: "기말고사")
        e.plan = offsets.enumerated().map { i, d in
            ExamPlanItem(day: today.adding(days: d), target: ExamPlanTarget(kind: .custom), title: "항목 \(i)")
        }
        return e
    }

    func days(_ items: [ExamPlanItem]) -> [Int] { items.map { today.days(until: $0.day) } }

    @Test func showsThreeDaysFromToday() {
        let w = exam([-2, 0, 1, 1, 3, 5]).planWindow(today: today, days: 3)
        #expect(days(w.shown) == [0, 1, 1])
        #expect(days(w.folded) == [-2, 3, 5])
    }

    @Test func aPlanThatStartsLaterShowsItsFirstDays() {
        // 오늘부터 사흘에 항목이 없으면 계획의 첫 날(닷새 뒤)부터 사흘을 보인다.
        let w = exam([5, 6, 9]).planWindow(today: today, days: 3)
        #expect(days(w.shown) == [5, 6])
        #expect(days(w.folded) == [9])
    }

    @Test func onlyPastItemsAreAllFolded() {
        let w = exam([-3, -1]).planWindow(today: today, days: 3)
        #expect(w.shown.isEmpty && days(w.folded) == [-3, -1])
    }

    @Test func removedItemsAreNeitherShownNorFolded() {
        var e = exam([0, 1])
        e.plan[0].removed = true
        let w = e.planWindow(today: today, days: 3)
        #expect(days(w.shown) == [1] && w.folded.isEmpty)
    }

    @Test func theWindowSplitsEveryItemOnce() async {
        await propertyCheck(input: Gen.int(in: -10...20).array(of: 0...12), Gen.int(in: 1...7)) { offsets, n in
            let w = exam(offsets).planWindow(today: today, days: n)
            #expect(w.shown.count + w.folded.count == offsets.count)
            let shownDays = days(w.shown)
            if let lo = shownDays.min(), let hi = shownDays.max() { #expect(hi - lo < n && lo >= 0) }
            #expect(w.shown.isEmpty == !offsets.contains { $0 >= 0 })
        }
    }
}
