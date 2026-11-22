import FolioDomain
import Foundation

// 풀기 화면을 여는 요청이다. 문제를 고르면 그 문제를 바로 풀고, 비우면 단원이나 묶음의 문제로 고르기부터 시작한다.
// 화면은 이 요청을 `folio://course/<ID>/solve?…` 주소로 연다. 창의 기록이 주소로 같은 풀기를 다시 열기 때문이다.
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

    // 주소에 풀기 ID가 없으면(손으로 쓴 주소) 과목마다 같은 ID를 쓴다. 그래야 그 주소를 다시 열 때 같은 풀기로 돌아온다.
    init(course: UUID, query: AppLink.Solve) {
        self.init(
            id: query.run ?? course, course: course, units: query.units, set: query.set, problems: query.problems,
            planItem: query.plan, mode: query.mode, shuffled: query.shuffled, minutes: query.minutes)
    }

    var link: AppLink {
        .solve(
            course,
            AppLink.Solve(
                run: id, units: units, set: set, problems: problems, plan: planItem, mode: mode, shuffled: shuffled, minutes: minutes))
    }
}

extension OpenLinkAction {
    // 풀기는 그 칸에서 연다. 풀던 화면을 칸의 기록에 남겨야 끝내거나 닫을 때 연 곳으로 돌아오기 때문이다.
    @MainActor func solve(_ request: SolveRequest) { self(request.link, course: request.course) }
}
