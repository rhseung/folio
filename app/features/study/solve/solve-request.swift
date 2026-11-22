import FolioDomain
import Foundation

// 풀기 시트를 여는 요청이다. 문제를 고르면 그 문제를 바로 풀고, 비우면 단원이나 묶음의 문제로 시트가 고르기부터 시작한다.
struct SolveRequest: Identifiable, Equatable {
    var id = UUID()
    var course: UUID
    var units: [UUID] = []
    var set: UUID?
    var problems: [UUID] = []
    // 계획 항목에서 열면 풀기를 끝낼 때 그 항목을 체크한다(섞어 풀기, 모의시험).
    var planItem: UUID?
    var mode: SolveMode?
    // 계획의 섞어 풀기와 모의시험은 섞은 순서로 열고 단원 표시를 가린다.
    var shuffled = false
    // 모의시험의 제한 시간이다. 빼면 다음 시험의 시간이나 설정의 기본값이다.
    var minutes: Int?
}

extension SolveRequest {
    init(plan: PlanSolve, course: UUID, item: UUID) {
        self.init(
            course: course, problems: plan.problems, planItem: item, mode: plan.mode, shuffled: plan.shuffled, minutes: plan.minutes)
    }
}
