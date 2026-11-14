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
                        "\(other)\(ClockText.duration(elapsed, hours: true))",
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
