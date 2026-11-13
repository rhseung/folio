import Foundation
import Observation

/// Recordings being transcribed from their audio, one after another. Kept by the workspace so a job goes on after
/// the player that started it closes.
@MainActor @Observable
final class TranscriptionQueue {
    private(set) var phases: [UUID: TranscriptionPhase] = [:]
    @ObservationIgnored private var jobs: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var last: Task<Void, Never>?

    func phase(of id: UUID) -> TranscriptionPhase? { phases[id] }

    /// `work` gets a way to report its progress; it throws `CancellationError` when cancelled. Asking again for a
    /// recording already queued does nothing.
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

    // The token keeps a late report or the end of a cancelled job from touching a newer job for the same recording.
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
