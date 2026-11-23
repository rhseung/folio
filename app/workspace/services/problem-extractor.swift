import FolioAI
import FolioActions
import Foundation
import Observation

// 문제 뽑기는 비용이 드는 Claude 호출이라 하나씩 차례로 한다. 뽑은 문제는 `problem-set propose`로 초안이 되므로, 이 큐는
// 진행과 실패만 자료마다 들고 있다. 실패는 파일에 남기지 않아 앱을 다시 열면 사라진다.
@MainActor @Observable
final class ProblemExtractor {
    enum State: Equatable {
        case waiting
        case running
        case failed(String)
    }

    private(set) var states: [UUID: State] = [:]
    @ObservationIgnored private var last: Task<Void, Never>?
    // 테스트는 가짜 프로바이더를 준다. 테스트 host는 이 Mac의 Claude에 닿지 않는다(`Workspace.claudeReady`).
    @ObservationIgnored var standIn: (@MainActor (LoadedCourse) -> ClaudeClient)?

    func state(of material: UUID) -> State? { states[material] }

    var isBusy: Bool { states.values.contains { $0 == .waiting || $0 == .running } }

    func clear(_ material: UUID) {
        if case .failed? = states[material] { states[material] = nil }
    }

    func enqueue(_ material: UUID, work: @escaping @MainActor () async throws -> Void) {
        // 뽑는 중인 자료를 다시 넣지 않는다. 실패한 자료는 다시 넣는다.
        if let state = states[material], !isFailed(state) { return }
        states[material] = .waiting
        let before = last
        let job = Task { [weak self] in
            await before?.value
            self?.states[material] = .running
            do {
                try await work()
                self?.states[material] = nil
            } catch {
                self?.states[material] = .failed(Self.message(for: error))
            }
        }
        last = job
    }

    // 테스트가 뽑기가 끝나기를 기다린다.
    func finish() async { await last?.value }

    // 규칙에 막힌 액션(뽑은 문제 없음, 자료 없음)은 액션의 문구를, Claude 호출의 실패는 Claude 패널과 같은 문구를 보인다.
    nonisolated static func message(for error: any Error) -> String {
        if let refusal = error as? ActionError { return refusal.description }
        return ClaudeFailure.message(for: error)
    }

    private func isFailed(_ state: State) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
