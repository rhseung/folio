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
            // folio:not-an-action recording is not an action
            try pending.save(PendingRecording(courseId: course.id, recording: recording))
            recorder.saveTranscript = { [store = course.store] recording, transcript in try? store.saveTranscript(transcript, of: recording) }
            // folio:not-an-action recording is not an action
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
        guard let course = course(id), recorder.current != recording.id, !finishingRecordings.contains(recording.id) else { return }
        transcriptions.cancel(recording.id)
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
        for pending in pendingRecordings.all() where pending.recording.id != recorder.current {
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
            // Captions missing (the language model was still downloading, or a crash) are made from the audio now;
            // Whisper redoes them all, since it hears Korean and English together where the captions take one language.
            let heard = course.store.transcript(of: recording)?.lines.isEmpty == false
            if !heard || TranscriptionEngine.preferred == .whisper { transcribe(recording, course: course.id) }
        } catch {
            self.error = String(localized: .recordingErrorInstallFailed(error.localizedDescription))
        }
    }

    /// Replaces the transcript with one made from the whole audio. Goes on after the player closes; a recording
    /// already queued is not queued again.
    func transcribe(_ recording: Recording, course id: UUID, engine: TranscriptionEngine = .preferred) {
        guard let course = course(id), recording.hasAudio else { return }
        let store = course.store
        // The captions saved the language picked when recording began, even when they heard nothing.
        let locale = Locale(identifier: store.transcript(of: recording)?.locale ?? "ko-KR")
        let copy = URL.cachesDirectory.appending(path: "Folio/Transcribing/\(recording.id.uuidString).\((recording.file as NSString).pathExtension)")
        transcriptions.run(recording.id, failed: { [weak self] error in
            self?.error = String(localized: .recordingErrorTranscribeFailed(error.localizedDescription))
        }) { report in
            // folio:not-an-action a copy in this device's caches, outside the GIST folder
            defer { try? FileManager.default.removeItem(at: copy) }
            try store.copyAudio(of: recording, to: copy)
            let transcript = try await engine.transcribe(copy, locale: locale, report: report)
            // Deleted meanwhile: saving now would leave a transcript with no recording.
            try Task.checkCancellation()
            // folio:not-an-action a transcript is the recording's output, like the captions saved while recording
            try store.saveTranscript(transcript, of: recording)
        }
    }

    /// Recording is not an action, so its list is the one place the app writes course.json itself.
    private func editRecordings(_ course: UUID, _ change: (inout [Recording]) -> Void) {
        guard let gist else { return }
        let ctx = ActionContext(gist: gist, device: device, calendar: calendar, courses: Dictionary(courses.map { ($0.id, $0.store) }, uniquingKeysWith: { a, _ in a }))
        perform { try ctx.edit(course) { change(&$0.recordings) } }
        show(ctx)
    }
}
