import FolioDomain
import Observation
import SwiftUI

#if os(macOS)
import AppKit
#endif

extension View {
    func studyTime(course id: UUID) -> some View {
        modifier(StudyTimeModifier(courseID: id))
    }
}

private struct StudyTimeModifier: ViewModifier {
    @Environment(Workspace.self) private var workspace
    @Environment(\.scenePhase) private var scenePhase
    let courseID: UUID

    func body(content: Content) -> some View {
        content
            .onAppear { StudyTracker.shared.enter(courseID, workspace: workspace) }
            .onDisappear { StudyTracker.shared.leave(courseID) }
            #if os(iOS)
        .onChange(of: scenePhase) { _, phase in StudyTracker.shared.setActive(phase == .active) }
            #endif
    }
}
