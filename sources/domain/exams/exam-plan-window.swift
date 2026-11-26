import FolioCore
import Foundation

extension Exam {
    // 단원 페이지가 펼쳐 보일 계획 항목과 "더 보기"로 접을 항목이다. 오늘부터 `days`일의 항목을 보이고, 지난 날과 그
    // 뒤의 날은 접는다. 오늘부터 그 날들에 항목이 없으면(계획이 다음 주에 시작) 항목이 있는 첫 날부터 센다. 그러지
    // 않으면 계획이 있어도 펼친 줄이 하나도 없다.
    public func planWindow(today: LocalDate, days: Int) -> (shown: [ExamPlanItem], folded: [ExamPlanItem]) {
        let items = plan.filter { !$0.isRemoved }.sorted { ($0.day, $0.title) < ($1.day, $1.title) }
        guard let first = items.map(\.day).first(where: { $0 >= today }) else { return ([], items) }
        let start = first < today.adding(days: max(days, 1)) ? today : first
        let end = start.adding(days: max(days, 1))
        let shown = items.filter { $0.day >= start && $0.day < end }
        return (shown, items.filter { !($0.day >= start && $0.day < end) })
    }
}
