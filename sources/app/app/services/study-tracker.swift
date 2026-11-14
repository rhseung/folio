import FolioDomain
import Observation
import SwiftUI

#if os(macOS)
import AppKit
#endif

@MainActor @Observable
final class StudyTracker {
    static let shared = StudyTracker()

    private(set) var revision = 0
    private(set) var manual: (courseId: UUID, start: Date)?

    @ObservationIgnored private var course: UUID?
    @ObservationIgnored private var span: ActivitySpan?
    @ObservationIgnored private weak var workspace: Workspace?
    @ObservationIgnored private var appActive = true

    private init() {
        #if os(macOS)
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
