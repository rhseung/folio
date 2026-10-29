import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    var pendingRecordings: PendingRecordings {
        PendingRecordings(url: URL.applicationSupportDirectory.appending(path: "Folio/Recording", directoryHint: .isDirectory))
    }

    func startRecording(_ session: Session, in course: LoadedCourse, locale: Locale) async {
        guard !recorder.isActive else { return }
        let pending = pendingRecordings
        var started: UUID?
        do {
            // Names of recordings still being compressed are taken too, though their audio isn't in the folder yet.
            let file = try course.store.newRecordingFile(named: course.file.name(of: session), reserved: course.file.recordings.map(\.file))
            let recording = Recording(device: device, at: .now, sessionId: session.id, file: file)
            started = recording.id
            // folio:not-an-action recording is not an action (docs/SPEC.md "액션")
            try pending.save(PendingRecording(courseId: course.id, recording: recording))
            recorder.saveTranscript = { [store = course.store] recording, transcript in try? store.saveTranscript(transcript, of: recording) }
            // folio:not-an-action recording is not an action (docs/SPEC.md "액션")
            recorder.saveProgress = { [id = course.id] recording in try? pending.save(PendingRecording(courseId: id, recording: recording)) }
            try await recorder.start(recording, at: pending.audioURL(of: recording.id), course: course.id,
                                     title: "\(course.file.course.title) · \(course.file.name(of: session))", locale: locale)
            // Listed from the start, so the session shows it is being recorded.
            editRecordings(course.id) { $0.append(recording) }
        } catch {
            if let started { pending.remove(started) }
            self.error = error.localizedDescription
        }
    }

    /// The entry goes first: a file left behind by a failed delete is harmless, an entry pointing at nothing is not.
    func deleteRecording(_ recording: Recording, course id: UUID) {
        guard let course = course(id), recorder.recording?.id != recording.id, !finishingRecordings.contains(recording.id) else { return }
        editRecordings(id) { $0.removeAll { $0.id == recording.id } }
        perform { try course.store.deleteFiles(of: recording) }
    }

    func stopRecording() async {
        // Stopped first, whatever happens to the course: the microphone must not stay on.
        guard let id = recorder.courseId, let (recording, transcript) = await recorder.stop() else { return }
        if let course = course(id) { perform { try course.store.saveTranscript(transcript, of: recording) } }
        await finishRecording(PendingRecording(courseId: id, recording: recording))
    }

    /// Recordings left on this device by a quit or a crash. The one being recorded is not among them.
    func recoverRecordings() {
        for pending in pendingRecordings.all() where pending.recording.id != recorder.recording?.id {
            Task { await finishRecording(pending) }
        }
    }

    /// Compresses the audio into the course folder and lists it with its length. On failure the audio stays on this
    /// device and is tried again at the next launch.
    private func finishRecording(_ pending: PendingRecording) async {
        let id = pending.recording.id
        guard let course = course(pending.courseId), finishingRecordings.insert(id).inserted else { return }
        defer { finishingRecordings.remove(id) }
        let local = pendingRecordings
        var recording = pending.recording
        do {
            recording.duration = try await Task.detached { try LectureRecorder.compress(local.audioURL(of: id), to: local.compressedURL(of: id)) }.value
            let path = try course.store.installRecording(from: local.compressedURL(of: id), as: recording.file)
            if path != recording.file {
                // shortcut: the transcript is copied under the new name and the old one is left; only two devices recording the same session collide.
                let transcript = course.store.transcript(of: recording)
                recording.file = path
                if let transcript { try? course.store.saveTranscript(transcript, of: recording) }
            }
            editRecordings(course.id) { list in
                if let i = list.firstIndex(where: { $0.id == id }) { list[i] = recording } else { list.append(recording) }
            }
            local.remove(id)
        } catch {
            self.error = String(localized: .recordingErrorInstallFailed(error.localizedDescription))
        }
    }

    /// Recording is not an action (docs/SPEC.md "액션"), so its list is the one place the app writes course.json itself.
    private func editRecordings(_ course: UUID, _ change: (inout [Recording]) -> Void) {
        guard let gist else { return }
        let ctx = ActionContext(gist: gist, device: device, calendar: calendar, courses: Dictionary(courses.map { ($0.id, $0.store) }, uniquingKeysWith: { a, _ in a }))
        perform { try ctx.edit(course) { change(&$0.recordings) } }
        show(ctx)
    }
}
