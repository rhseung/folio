import FolioDomain
import Foundation

// 풀다 둔 차례다(#576 "풀던 차례"). 판정은 문제마다 로그에 바로 쓰므로 남길 것은 차례뿐이고, 앱을 끄면 사라져도 잃는 기록이 없다.
// 그래서 파일에 쓰지 않고 과목마다 앱의 메모리에 둔다.
struct SolveResume: Equatable {
    var queue: [UUID]
    var index: Int
    var mode: SolveMode
    var order: SolvePick.Order
    var runId: UUID
    var done: Int

    @MainActor private static var store: [UUID: SolveResume] = [:]

    @MainActor static func remember(_ resume: SolveResume, for course: UUID) { store[course] = resume }

    @MainActor static func clear(for course: UUID) { store[course] = nil }

    // 그사이 지운 문제는 차례에서 뺀다. 남은 문제가 없으면 이어 풀 것이 없다.
    @MainActor static func saved(for course: UUID, in workspace: Workspace) -> SolveResume? {
        guard var saved = store[course], let study = workspace.study(of: course) else { return nil }
        let head = saved.queue.prefix(saved.index).filter { study.problems[$0] != nil }
        let rest = saved.queue.dropFirst(saved.index).filter { study.problems[$0] != nil }
        guard !rest.isEmpty else {
            store[course] = nil
            return nil
        }
        saved.queue = head + rest
        saved.index = head.count
        return saved
    }
}
