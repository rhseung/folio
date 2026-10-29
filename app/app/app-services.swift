import FolioDomain
import SwiftUI

extension View {
    /// Background work tied to the open GIST folder: notification rescheduling and the daily backup.
    func appServices() -> some View {
        modifier(AppServices())
    }
}

private struct AppServices: ViewModifier {
    @Environment(Workspace.self) private var workspace

    /// What the notification plan reads; any change reschedules.
    struct PlanInputs: Equatable {
        var settings: NotificationSettings
        var edits: [Date]
        var reviews: Int
        var semester: UUID?
    }

    var inputs: PlanInputs {
        PlanInputs(settings: workspace.settings.notifications, edits: workspace.courses.map(\.file.course.updatedAt),
                   reviews: workspace.reviewEvents.values.map(\.count).reduce(0, +), semester: workspace.currentSemester?.id)
    }

    func body(content: Content) -> some View {
        content
            .task(id: inputs) {
                guard workspace.gist != nil, !workspace.runsOnFixture else { return }
                // Edits come in bursts (typing in a field saves often); wait for them to settle.
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await NotificationScheduler.reschedule(workspace)
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
            #endif
    }
}
