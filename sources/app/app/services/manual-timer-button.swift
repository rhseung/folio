import FolioDomain
import Observation
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ManualTimerButton: View {
    @Environment(Workspace.self) private var workspace
    let courseID: UUID

    var body: some View {
        let tracker = StudyTracker.shared
        if let manual = tracker.manual {
            Button {
                tracker.stopManual()
            } label: {
                TimelineView(.periodic(from: manual.start, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(manual.start))
                    let other = manual.courseId == courseID ? "" : (workspace.course(manual.courseId)?.title ?? "") + " "
                    Label(
                        "\(other)\(String(format: "%d:%02d:%02d", elapsed / 3600, elapsed / 60 % 60, elapsed % 60))",
                        systemImage: "stop.fill"
                    )
                    .monospacedDigit()
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, Theme.Space.s)
                }
            }
            .help(Text(.timerStopHelp))
        } else {
            Button(.timerStart, systemImage: "timer") { tracker.startManual(courseID, workspace: workspace) }
                .help(Text(.timerStartHelp))
        }
    }
}
