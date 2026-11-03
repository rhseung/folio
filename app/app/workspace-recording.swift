import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    func startRecording(_ session: Session, in course: LoadedCourse) async {
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
                                     title: "\(course.file.course.title) · \(course.file.name(of: session))", locale: captionLocale(of: course))
            // Listed from the start, so the session shows it is being recorded.
            editRecordings(course.id) { $0.append(recording) }
            await tellCaptions()
        } catch {
            if let started { pending.remove(started) }
            self.error = error.localizedDescription
        }
    }

    /// Reads the slides for the recording under way and gives the captions what they say. The PDFs may have to
    /// download first, so this runs after recording has started, never before.
    func tellCaptions() async {
        guard let id = recorder.current, let course = recorder.courseId.flatMap(course), let snapshot = recorder.snapshot,
              let session = course.file.sessions.first(where: { $0.id == snapshot.sessionId }) else { return }
        let (store, file, telling) = (course.store, course.file, recorder.telling())
        let context = await Task.detached { store.transcriptionContext(file, session: session, recording: snapshot) }.value
        await recorder.use(context, hints: context.hints(course: file.course.title), for: id, telling: telling)
    }

    /// Again only when the slides or units would now be others: reading the PDFs takes a while.
    func retellCaptionsIfChanged() {
        guard let course = recorder.courseId.flatMap(course), let snapshot = recorder.snapshot,
              let session = course.file.sessions.first(where: { $0.id == snapshot.sessionId }) else { return }
        let now = course.file.transcriptionContext(for: session, recording: snapshot)
        guard recorder.context.map({ $0.differs(from: now) }) ?? true else { return }
        Task { await tellCaptions() }
    }

    /// A page of a lecture file came on screen in the app (nil: the file closed). Kept with the recording when it is
    /// of the course being recorded; turning to a page past what the captions were told tells them again.
    func showing(page: Int?, of material: FolioDomain.Material, course: UUID) {
        guard recorder.courseId == course, recorder.isActive, material.role == .lecture else { return }
        recorder.show(material.id, page: page)
        retellCaptionsIfChanged()
        if let id = recorder.current, let visit = recorder.pages.last, visit.page != nil { retellAfterDwell(on: visit, recording: id) }
    }

    /// A page counts once it has stayed `pageDwell`, so at the turn itself the captions can't be told it yet: without
    /// a second look they would always be a page behind, and a class kept on one page would never reach them. Waits
    /// on the audio's clock, which stops while paused.
    private func retellAfterDwell(on visit: PageVisit, recording id: UUID) {
        Task {
            while recorder.current == id, recorder.pages.last == visit {
                let left = visit.at + Recording.pageDwell - recorder.elapsed
                if left <= 0 { return retellCaptionsIfChanged() }
                try? await Task.sleep(for: .seconds(left + 0.5))
            }
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
        guard let id = recorder.courseId, let (recording, captions) = await recorder.stop() else { return }
        if let course = course(id) { perform { try course.store.saveTranscript(captions, of: recording) } }
        await finishRecording(PendingRecording(courseId: id, recording: recording))
    }

    /// Recordings left on this device by a quit or a crash. The one being recorded is not among them. Each is tried
    /// once per launch: every reload asks (a course can arrive by sync later), and a failure would show its dialog again
    /// on every file change.
    func recoverRecordings() {
        for pending in pendingRecordings.all() where pending.recording.id != recorder.current && course(pending.courseId) != nil {
            guard recoveryTried.insert(pending.recording.id).inserted else { continue }
            Task { await finishRecording(pending) }
        }
    }

    /// Compresses the audio into the course folder and lists it with its length. On failure the audio stays on this
    /// device and is tried again at the next launch.
    private func finishRecording(_ pending: PendingRecording) async {
        let id = pending.recording.id
        guard let course = course(pending.courseId), finishingRecordings.insert(id).inserted else { return }
        // Here rather than only in recovery, so one that failed right after stopping isn't tried again on a reload.
        recoveryTried.insert(id)
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
            await retellFinished(recording, in: course)
            // The pages the class went through become the session's range, for files it has none for yet.
            if !recording.pages.isEmpty, let session = recording.sessionId, course.file.sessions.contains(where: { $0.id == session }) {
                _ = run(SessionLinkViewed(course: course.id, session: session))
            }
            // Captions missing (the language model was still downloading, or a crash) are made from the audio now;
            // Whisper redoes them all, since it hears Korean and English together where the captions take one language.
            let heard = course.store.transcript(of: recording)?.reaches(recording.duration) == true
            if !heard || TranscriptionEngine.preferred == .whisper { transcribe(recording, course: course.id, asked: false) }
        } catch {
            self.error = String(localized: .recordingErrorInstallFailed(error.localizedDescription))
        }
    }

    /// The captions were told the context at the last page turn, before the page then on screen had stayed long enough
    /// to count, and a quit or a crash saves that same context. Made again from the whole recording, here where a stop
    /// and a recovery both pass, it is what the player compares the course with; left as it was, the player would
    /// say the materials changed when nothing had.
    private func retellFinished(_ recording: Recording, in course: LoadedCourse) async {
        guard var transcript = course.store.transcript(of: recording),
              let session = course.file.sessions.first(where: { $0.id == recording.sessionId }) else { return }
        let (store, file) = (course.store, course.file)
        let context = await Task.detached { store.transcriptionContext(file, session: session, recording: recording) }.value
        guard transcript.context != context else { return }
        transcript.context = context
        perform { try store.saveTranscript(transcript, of: recording) }
    }

    /// Replaces the transcript with one made from the whole audio. Goes on after the player closes; a recording
    /// already queued is not queued again. Unless someone `asked`, the Whisper model is used only if it is already
    /// here, and Apple's recognizer does without it.
    func transcribe(_ recording: Recording, course id: UUID, engine: TranscriptionEngine = .preferred, asked: Bool = true) {
        guard let course = course(id), recording.hasAudio else { return }
        let mayDownload = asked || WhisperModel.shared.ready
        let engine = engine == .whisper && !mayDownload ? .apple : engine
        // Captions already there are better than a redo by the same recognizer.
        if !asked, engine == .apple, course.store.transcript(of: recording)?.reaches(recording.duration) == true { return }
        let store = course.store
        // Only Apple's recognizer needs it. A crash before the first caption leaves no transcript to say what the
        // captions listened for, but they chose it the same way.
        let locale = store.transcript(of: recording).map { Locale(identifier: $0.locale) } ?? captionLocale(of: course)
        let file = course.file
        let session = file.sessions.first { $0.id == recording.sessionId }
        // The listed one has the pages the recording kept; the caller's copy may be from before it finished.
        let recording = file.recordings.first { $0.id == recording.id } ?? recording
        let copy = URL.cachesDirectory.appending(path: "Folio/Transcribing/\(recording.id.uuidString).\((recording.file as NSString).pathExtension)")
        transcriptions.run(recording.id, failed: { [weak self] error in
            self?.error = String(localized: .recordingErrorTranscribeFailed(error.localizedDescription))
        }) { report in
            // folio:not-an-action a copy in this device's caches, outside the GIST folder
            defer { try? FileManager.default.removeItem(at: copy) }
            try store.copyAudio(of: recording, to: copy)
            let context = session.map { store.transcriptionContext(file, session: $0, recording: recording) }
            var transcript = try await engine.transcribe(copy, locale: locale, hints: context?.hints(course: file.course.title), mayDownload: mayDownload, report: report)
            transcript.context = context
            // Deleted meanwhile: saving now would leave a transcript with no recording.
            try Task.checkCancellation()
            guard transcript.replaces(store.transcript(of: recording)) else { return }
            // folio:not-an-action a transcript is the recording's output, like the captions saved while recording
            try store.saveTranscript(transcript, of: recording)
        }
    }

    /// Captions take one language, so they follow the course's last transcript, which Whisper heard for itself.
    private func captionLocale(of course: LoadedCourse) -> Locale {
        let latest = course.file.recordings.sorted { $0.createdAt > $1.createdAt }.lazy.compactMap { course.store.transcript(of: $0) }.first
        return Locale(identifier: latest?.locale ?? "ko-KR")
    }

    /// Recording is not an action, so its list is the one place the app writes course.json itself.
    private func editRecordings(_ course: UUID, _ change: (inout [Recording]) -> Void) {
        guard let gist else { return }
        let ctx = ActionContext(gist: gist, device: device, calendar: calendar, courses: Dictionary(courses.map { ($0.id, $0.store) }, uniquingKeysWith: { a, _ in a }))
        perform { try ctx.edit(course) { change(&$0.recordings) } }
        show(ctx)
    }
}
