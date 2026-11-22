import FolioDomain
import SwiftUI

extension View {
    func appServices() -> some View {
        modifier(AppServices())
    }
}

private struct AppServices: ViewModifier {
    @Environment(Workspace.self) private var workspace
    @State private var lmsSync: Task<Void, Never>?
    @State private var lmsTried: Date?

    struct PlanInputs: Equatable {
        var settings: NotificationSettings
        var edits: [Date]
        var study: Int
        var semester: UUID?
    }

    struct LMSInputs: Equatable {
        var gist: URL?
        var connected: Bool
    }

    var inputs: PlanInputs {
        PlanInputs(
            settings: workspace.settings.notifications, edits: workspace.courses.map(\.file.course.updatedAt),
            study: workspace.studyRevision, semester: workspace.currentSemester?.id)
    }

    // 동기화가 1분보다 오래 걸릴 수 있어 시계가 다시 움직여도 끊지 않는다. 그래서 `.task(id:)`가 아니라 따로 둔 Task다.
    private func syncLMSIfDue() {
        guard workspace.gist != nil, !workspace.runsOnFixture, workspace.lms.isConnected, lmsSync == nil,
            workspace.settings.lms.syncDue(lastAttempt: lmsTried, now: .now)
        else { return }
        lmsTried = .now
        lmsSync = Task {
            await workspace.syncLMS()
            lmsSync = nil
        }
    }

    func body(content: Content) -> some View {
        content
            .task(id: inputs) {
                guard workspace.gist != nil, !workspace.runsOnFixture else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await NotificationScheduler.reschedule(workspace)
            }
            // 시계는 분마다, 그리고 앱이 앞으로 오거나 Mac이 깨어날 때 움직인다. 그때마다 확인 주기가 지났는지 본다. 잠든 동안
            // 기다리던 `Task.sleep`은 깨어난 뒤 바로 끝나지 않는다.
            .onChange(of: workspace.liveNow, initial: true) { syncLMSIfDue() }
            .onChange(of: workspace.gist == nil ? nil : workspace.liveToday, initial: true) { _, day in
                if day != nil { workspace.replanExams() }
            }
            .onChange(of: LMSInputs(gist: workspace.gist?.url, connected: workspace.lms.isConnected)) {
                lmsTried = nil
                syncLMSIfDue()
            }
            #if os(macOS)
        .task(id: workspace.gist?.url) {
            while !Task.isCancelled {
                await workspace.backUpIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
            #endif
            #if DEBUG && os(macOS)
        .onAppear { SnapshotDriver.shared.extraCaptures = { await FormSnapshots.capture(workspace, into: $0) } }
        .snapshotKey()
        #endif
    }
}
