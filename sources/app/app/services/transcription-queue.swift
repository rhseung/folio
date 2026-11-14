import Foundation
import Observation

@MainActor @Observable
final class TranscriptionQueue {
    private(set) var phases: [UUID: TranscriptionPhase] = [:]
    @ObservationIgnored private var jobs: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var last: Task<Void, Never>?

    func phase(of id: UUID) -> TranscriptionPhase? { phases[id] }

    func run(
        _ id: UUID, failed: @escaping @MainActor (any Error) -> Void,
        _ work: @escaping @Sendable (@escaping @Sendable (TranscriptionPhase) -> Void) async throws -> Void
    ) {
        guard jobs[id] == nil else { return }
        phases[id] = .waiting
        let before = last
        let token = UUID()
        let report: @Sendable (TranscriptionPhase) -> Void = { [weak self] phase in
            Task { @MainActor [weak self] in self?.update(id, token, phase) }
        }
        let job = Task { [weak self] in
            await before?.value
            defer { self?.finish(id, token) }
            guard !Task.isCancelled else { return }
            do {
                try await work(report)
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { failed(error) }
            }
        }
        jobs[id] = (token, job)
        last = job
    }

    func cancel(_ id: UUID) {
        guard let job = jobs[id] else { return }
        job.task.cancel()
        finish(id, job.token)
    }

    // token이 있어야 늦게 온 보고나 취소된 작업의 끝이 같은 녹음의 새 작업을 바꾸지 않는다.
    private func update(_ id: UUID, _ token: UUID, _ phase: TranscriptionPhase) {
        guard jobs[id]?.token == token else { return }
        phases[id] = phase
    }

    private func finish(_ id: UUID, _ token: UUID) {
        guard jobs[id]?.token == token else { return }
        jobs[id] = nil
        phases[id] = nil
    }
}
