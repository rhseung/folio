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
            // 아직 압축 중인 녹음의 오디오는 폴더에 없지만, 그 이름도 이미 쓴 것으로 본다.
            let file = try course.store.newRecordingFile(
                named: course.file.recordingName(of: session, calendar: calendar), reserved: course.file.recordings.map(\.file))
            let recording = Recording(device: device, at: .now, sessionId: session.id, file: file)
            started = recording.id
            // folio:not-an-action recording is not an action
            try pending.save(PendingRecording(courseId: course.id, recording: recording))
            recorder.saveTranscript = { [store = course.store] recording, transcript in try? store.saveTranscript(transcript, of: recording)
            }
            // folio:not-an-action recording is not an action
            recorder.saveProgress = { [id = course.id] recording in try? pending.save(PendingRecording(courseId: id, recording: recording))
            }
            try await recorder.start(
                recording, at: pending.audioURL(of: recording.id), course: course.id,
                title: "\(course.file.course.title) · \(course.file.title(of: session, calendar: calendar))",
                locale: captionLocale(of: course))
            editRecordings(course.id) { $0.append(recording) }
            await tellCaptions()
        } catch {
            if let started { pending.remove(started) }
            self.error = error.localizedDescription
        }
    }

    func tellCaptions() async {
        guard let id = recorder.current, let course = recorder.courseId.flatMap(course), let snapshot = recorder.snapshot,
            let session = course.file.sessions.first(where: { $0.id == snapshot.sessionId })
        else { return }
        let (store, file, telling) = (course.store, course.file, recorder.telling())
        let context = await Task.detached { store.transcriptionContext(file, session: session, recording: snapshot) }.value
        await recorder.use(context, hints: context.hints(course: file.course.title), for: id, telling: telling)
    }

    func retellCaptionsIfChanged() {
        guard let course = recorder.courseId.flatMap(course), let snapshot = recorder.snapshot,
            let session = course.file.sessions.first(where: { $0.id == snapshot.sessionId })
        else { return }
        let now = course.file.transcriptionContext(for: session, recording: snapshot)
        guard recorder.context.map({ $0.differs(from: now) }) ?? true else { return }
        Task { await tellCaptions() }
    }

    func showing(page: Int?, of material: FolioDomain.Material, course: UUID) {
        guard recorder.courseId == course, recorder.isActive, material.role == .lecture else { return }
        recorder.show(material.id, page: page)
        retellCaptionsIfChanged()
        if let id = recorder.current, let visit = recorder.pages.last, visit.page != nil { retellAfterDwell(on: visit, recording: id) }
    }

    // 쪽은 `pageDwell`만큼 머물러야 세므로, 넘기는 순간에는 자막에 알릴 수 없다. 다시 확인하지 않으면 자막은 늘 한 쪽
    // 뒤처지고, 한 쪽에 머문 수업에서는 그 쪽이 끝내 자막에 닿지 않는다. 일시 정지하면 멈추는 오디오의 시계로 기다린다.
    private func retellAfterDwell(on visit: PageVisit, recording id: UUID) {
        Task {
            while recorder.current == id, recorder.pages.last == visit {
                let left = visit.at + Recording.pageDwell - recorder.elapsed
                if left <= 0 { return retellCaptionsIfChanged() }
                try? await Task.sleep(for: .seconds(left + 0.5))
            }
        }
    }

    // 기록을 먼저 지운다. 삭제에 실패해 남은 파일은 해가 없지만, 없는 파일을 가리키는 기록은 문제를 만든다.
    func deleteRecording(_ recording: Recording, course id: UUID) {
        guard let course = course(id), recorder.current != recording.id, !finishingRecordings.contains(recording.id) else { return }
        transcriptions.cancel(recording.id)
        editRecordings(id) { $0.removeAll { $0.id == recording.id } }
        perform { try course.store.deleteFiles(of: recording) }
    }

    func stopRecording() async {
        // 과목에 무슨 일이 있어도 먼저 멈춘다. 마이크가 켜진 채 남으면 안 된다.
        guard let id = recorder.courseId, let (recording, captions) = await recorder.stop() else { return }
        askWrapUp(after: recording, course: id)
        if let course = course(id) { perform { try course.store.saveTranscript(captions, of: recording) } }
        await finishRecording(PendingRecording(courseId: id, recording: recording))
    }

    // 실행마다 한 번만 시도한다. 다시 읽을 때마다 묻고(과목이 나중에 동기화로 올 수 있다), 실패하면 파일이 바뀔 때마다
    // 대화상자가 다시 뜨기 때문이다.
    func recoverRecordings() {
        for pending in pendingRecordings.all() where pending.recording.id != recorder.current && course(pending.courseId) != nil {
            guard recoveryTried.insert(pending.recording.id).inserted else { continue }
            Task { await finishRecording(pending) }
        }
    }

    private func finishRecording(_ pending: PendingRecording) async {
        let id = pending.recording.id
        guard let course = course(pending.courseId), finishingRecordings.insert(id).inserted else { return }
        recoveryTried.insert(id)
        defer { finishingRecordings.remove(id) }
        let local = pendingRecordings
        var recording = pending.recording
        do {
            recording.duration = try await Task.detached {
                try LectureRecorder.compress(local.audioURL(of: id), to: local.compressedURL(of: id))
            }.value
            let path = try course.store.installRecording(from: local.compressedURL(of: id), as: recording.file)
            if path != recording.file {
                // shortcut: 받아쓰기를 새 이름으로 복사하고 옛 파일은 남긴다. 두 기기가 같은 회차를 녹음할 때만 이름이 겹친다.
                let transcript = course.store.transcript(of: recording)
                recording.file = path
                if let transcript { try? course.store.saveTranscript(transcript, of: recording) }
            }
            editRecordings(course.id) { list in
                if let i = list.firstIndex(where: { $0.id == id }) { list[i] = recording } else { list.append(recording) }
            }
            local.remove(id)
            await retellFinished(recording, in: course)

            // 본 쪽을 여기서 회차에 연결하지 않는다. 진도 시트가 그 범위를 쓰는 유일한 곳이고, 저장하지 않고 닫은 시트는 범위를
            // 비워 두어야 다시 열 때 지난 수업 다음부터 시작한다. 자막이 빠졌으면(언어 모델을 아직 내려받는 중이었거나 비정상
            // 종료되었으면) 지금 오디오로 만든다. Whisper는 한국어와 영어를 함께 듣고 자막은 한 언어만 받으므로, Whisper는 전부 다시
            // 만든다.
            let heard = course.store.transcript(of: recording)?.reaches(recording.duration) == true
            if !heard || TranscriptionEngine.preferred == .whisper { transcribe(recording, course: course.id, asked: false) }
        } catch {
            self.error = String(localized: .recordingErrorInstallFailed(error.localizedDescription))
        }
    }

    // 자막은 마지막으로 쪽을 넘길 때 맥락을 받았고, 그때 화면의 쪽은 아직 셀 만큼 머물지 않았다. 앱 종료나 비정상 종료도
    // 같은 맥락을 저장한다. player는 이 값을 과목과 비교하므로, 멈춤과 복구가 모두 지나는 여기서 녹음 전체로 다시 만든다.
    // 그대로 두면 아무것도 바뀌지 않았는데 player가 자료가 바뀌었다고 보인다.
    private func retellFinished(_ recording: Recording, in course: LoadedCourse) async {
        guard var transcript = course.store.transcript(of: recording),
            let session = course.file.sessions.first(where: { $0.id == recording.sessionId })
        else { return }
        let (store, file) = (course.store, course.file)
        let context = await Task.detached { store.transcriptionContext(file, session: session, recording: recording) }.value
        guard transcript.context != context else { return }
        transcript.context = context
        perform { try store.saveTranscript(transcript, of: recording) }
    }

    func transcribe(_ recording: Recording, course id: UUID, engine: TranscriptionEngine = .preferred, asked: Bool = true) {
        guard let course = course(id), recording.hasAudio else { return }
        let mayDownload = asked || WhisperModel.shared.ready
        let engine = engine == .whisper && !mayDownload ? .apple : engine
        if !asked, engine == .apple, course.store.transcript(of: recording)?.reaches(recording.duration) == true { return }
        let store = course.store
        let locale = store.transcript(of: recording).map { Locale(identifier: $0.locale) } ?? captionLocale(of: course)
        let file = course.file
        let session = file.sessions.first { $0.id == recording.sessionId }
        let recording = file.recordings.first { $0.id == recording.id } ?? recording
        let copy = URL.cachesDirectory.appending(
            path: "Folio/Transcribing/\(recording.id.uuidString).\((recording.file as NSString).pathExtension)")
        transcriptions.run(
            recording.id,
            failed: { [weak self] error in
                self?.error = String(localized: .recordingErrorTranscribeFailed(error.localizedDescription))
            }
        ) { report in
            // folio:not-an-action a copy in this device's caches, outside the GIST folder
            defer { try? FileManager.default.removeItem(at: copy) }
            try store.copyAudio(of: recording, to: copy)
            let context = session.map { store.transcriptionContext(file, session: $0, recording: recording) }
            var transcript = try await engine.transcribe(
                copy, locale: locale, hints: context?.hints(course: file.course.title), mayDownload: mayDownload, report: report)
            transcript.context = context
            try Task.checkCancellation()
            guard transcript.replaces(store.transcript(of: recording)) else { return }
            // folio:not-an-action a transcript is the recording's output, like the captions saved while recording
            try store.saveTranscript(transcript, of: recording)
        }
    }

    // 자막은 한 언어만 받으므로, Whisper가 스스로 언어를 들은 과목의 마지막 받아쓰기를 따른다.
    private func captionLocale(of course: LoadedCourse) -> Locale {
        let latest = course.file.recordings.sorted { $0.createdAt > $1.createdAt }.lazy.compactMap { course.store.transcript(of: $0) }.first
        return Locale(identifier: latest?.locale ?? "ko-KR")
    }

    // 녹음은 액션이 아니므로, 이 목록이 앱이 course.json을 직접 쓰는 유일한 곳이다.
    private func editRecordings(_ course: UUID, _ change: (inout [Recording]) -> Void) {
        guard let gist else { return }
        let ctx = ActionContext(
            gist: gist, device: device, calendar: calendar,
            courses: Dictionary(courses.map { ($0.id, $0.store) }, uniquingKeysWith: { a, _ in a }))
        perform { try ctx.edit(course) { change(&$0.recordings) } }
        show(ctx)
    }
}
