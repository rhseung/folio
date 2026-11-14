import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class RecordingBarModel {
    let workspace: Workspace

    init(workspace: Workspace) { self.workspace = workspace }

    var recorder: LectureRecorder { workspace.recorder }
    var recording: Bool { recorder.state == .recording }
    var preparing: Bool { recorder.state == .preparing }
    var paused: Bool { recorder.state == .paused }
    var settling: Bool { preparing || recorder.state == .stopping }
    var recentLines: [LectureTranscript.Line] { Array(recorder.lines.suffix(40)) }
    var course: LoadedCourse? { recorder.courseId.flatMap { workspace.course($0) } }
    var accent: CourseAccent { recorder.courseId.map { workspace.accent($0) } ?? CourseAccent.gray }
    var courseTitle: String { preparing ? String(localized: .recordingPreparing) : course?.title ?? recorder.title }
    var sessionLink: AppLink? {
        guard let course, let id = recorder.recording?.sessionId, let session = course.file.sessions.first(where: { $0.id == id }) else {
            return nil
        }
        if let note = session.roughNoteId ?? session.reviewNoteId { return AppLink(.note, note) }
        return .course(course.id, page: .sessions)
    }
    var sessionName: String? {
        guard let course, let id = recorder.recording?.sessionId, let session = course.file.sessions.first(where: { $0.id == id }) else {
            return nil
        }
        return course.file.title(of: session, calendar: workspace.calendar)
    }
    var line: String {
        recorder.volatile.isEmpty
            ? (recorder.lines.last?.text ?? recorder.transcriptionNote ?? String(localized: .recordingListening)) : recorder.volatile
    }

    var context: TranscriptionContext? { recorder.context }
    var contextSummary: String {
        context.map(TranscriptionContextText.summary) ?? String(localized: .recordingContextReading)
    }
    var materialsLink: AppLink? { course.map { .course($0.id, page: .materials) } }
    func retellCaptionsIfChanged() { workspace.retellCaptionsIfChanged() }

    func toggle() {
        if recording { recorder.pause() } else { workspace.perform { try recorder.resume() } }
    }

    func stop() async { await workspace.stopRecording() }
}
