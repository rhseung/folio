import FolioDomain
import Observation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Records study time (docs/SPEC.md "공부 시간"): automatically while a course screen is in front and the user is
/// active, and by hand with the manual timer for study done away from the app. Each finished span becomes one
/// `study_session` event in that course's device log.
@MainActor @Observable
final class StudyTracker {
    static let shared = StudyTracker()

    /// Bumped after each write so the today chart reloads.
    private(set) var revision = 0
    private(set) var manual: (courseId: UUID, start: Date)?

    @ObservationIgnored private var course: UUID?
    @ObservationIgnored private var span: ActivitySpan?
    @ObservationIgnored private weak var workspace: Workspace?
    @ObservationIgnored private var appActive = true

    private init() {
        #if os(macOS)
        // Local monitors see only events sent to this app, which is what "the user is active here" means.
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]) { event in
            MainActor.assumeIsolated { StudyTracker.shared.input() }
            return event
        }
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { StudyTracker.shared.setActive(true) }
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { StudyTracker.shared.setActive(false) }
        }
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                StudyTracker.shared.close()
                StudyTracker.shared.stopManual()
            }
        }
        #endif
    }

    func enter(_ courseId: UUID, workspace: Workspace) {
        close()
        self.workspace = workspace
        course = courseId
        if appActive { span = ActivitySpan(start: .now) }
    }

    func leave(_ courseId: UUID) {
        guard course == courseId else { return }
        close()
        course = nil
    }

    func setActive(_ active: Bool) {
        appActive = active
        if !active { close() } else if course != nil, span == nil { span = ActivitySpan(start: .now) }
    }

    func input() {
        guard let course, appActive else { return }
        guard var current = span else {
            span = ActivitySpan(start: .now)
            return
        }
        if let done = current.input(at: .now) { write(course, done, screen: "course") }
        span = current
    }

    private func close() {
        if let course, let span { write(course, span.end(at: .now), screen: "course") }
        span = nil
    }

    func startManual(_ courseId: UUID, workspace: Workspace) {
        stopManual()
        self.workspace = workspace
        manual = (courseId, .now)
    }

    func stopManual() {
        guard let manual else { return }
        write(manual.courseId, DateInterval(start: manual.start, end: .now), screen: "manual")
        self.manual = nil
    }

    private func write(_ courseId: UUID, _ interval: DateInterval, screen: String) {
        workspace?.logStudySession(course: courseId, interval, screen: screen)
        revision += 1
    }
}

extension View {
    /// Counts the time this course screen is in front as study time.
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

/// Start/stop for the manual timer. While it runs for another course, it shows that one so it can be stopped.
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
                    Label("\(other)\(String(format: "%d:%02d:%02d", elapsed / 3600, elapsed / 60 % 60, elapsed % 60))", systemImage: "stop.fill")
                        .monospacedDigit()
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, Theme.Space.s)
                }
            }
            .help("공부 타이머 멈추고 기록하기")
        } else {
            Button("공부 타이머", systemImage: "timer") { tracker.startManual(courseID, workspace: workspace) }
                .help("앱 밖에서 하는 공부 시간을 이 과목에 기록합니다")
        }
    }
}
