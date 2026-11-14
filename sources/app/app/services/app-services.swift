import FolioDomain
import SwiftUI

extension View {
    func appServices() -> some View {
        modifier(AppServices())
    }
}

private struct AppServices: ViewModifier {
    @Environment(Workspace.self) private var workspace

    struct PlanInputs: Equatable {
        var settings: NotificationSettings
        var edits: [Date]
        var reviews: Int
        var semester: UUID?
    }

    struct LMSInputs: Equatable {
        var gist: URL?
        var connected: Bool
    }

    var inputs: PlanInputs {
        PlanInputs(
            settings: workspace.settings.notifications, edits: workspace.courses.map(\.file.course.updatedAt),
            reviews: workspace.reviewEvents.values.map(\.count).reduce(0, +), semester: workspace.currentSemester?.id)
    }

    func body(content: Content) -> some View {
        content
            .task(id: inputs) {
                guard workspace.gist != nil, !workspace.runsOnFixture else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await NotificationScheduler.reschedule(workspace)
            }
            // LMS는 학교 전체가 쓰므로 30분보다 자주 읽지 않는다.
            .task(id: LMSInputs(gist: workspace.gist?.url, connected: workspace.lms.isConnected)) {
                guard workspace.gist != nil, !workspace.runsOnFixture, workspace.lms.isConnected else { return }
                while !Task.isCancelled {
                    await workspace.syncLMS()
                    try? await Task.sleep(for: .seconds(30 * 60))
                }
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
