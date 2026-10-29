import AVFoundation
import FolioDomain
import Speech
#if os(iOS)
import UIKit
#endif

/// Records a lecture and transcribes it on the device as it goes (docs/SPEC.md "강의 녹음"). One microphone tap feeds
/// both the audio file and the transcriber, so transcript times line up with the file even across pauses.
@MainActor @Observable
final class LectureRecorder {
    enum State { case idle, preparing, recording, paused }

    private(set) var state = State.idle
    private(set) var courseId: UUID?
    private(set) var recording: Recording?
    private(set) var title = ""
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    private(set) var lines: [LectureTranscript.Line] = []
    /// Words heard but not settled yet; they settle into `lines`.
    private(set) var volatile = ""
    private(set) var bookmarks: [TimeInterval] = []
    private(set) var locale = Locale(identifier: "ko-KR")
    private(set) var transcriptionNote: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var sink: AudioSink?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var lastTranscriptSave = Date.distantPast
    @ObservationIgnored var saveTranscript: (Recording, LectureTranscript) -> Void = { _, _ in }
    /// Keeps the bookmarks beside the audio, so a crash doesn't lose them.
    @ObservationIgnored var saveProgress: (Recording) -> Void = { _ in }
    @ObservationIgnored private var lastRestart = Date.distantPast

    var isActive: Bool { state != .idle }

    /// Starts recording into `file`, an uncompressed CAF on this device: unlike AAC, it stays readable up to the last
    /// buffer if the app dies mid-lecture. Transcription is best effort; the audio never waits on it.
    func start(_ recording: Recording, at file: URL, course: UUID, title: String, locale: Locale) async throws {
        guard state == .idle else { return }
        state = .preparing
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.microphoneDenied }
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let input = engine.inputNode.outputFormat(forBus: 0)
            guard input.sampleRate > 0, let fileFormat = AVAudioFormat(standardFormatWithSampleRate: input.sampleRate, channels: 1) else {
                throw RecorderError.noMicrophone
            }
            let audioFile = try AVAudioFile(forWriting: file, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: input.sampleRate, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)

            var transcription: (SpeechTranscriber, AVAudioFormat, Locale)?
            switch await Self.transcriber(for: locale) {
            case .ready(let t, let format, let supported): transcription = (t, format, supported)
            case .downloading: transcriptionNote = String(localized: .recorderModelDownloading)
            case .unsupported: transcriptionNote = String(localized: .recorderLocaleAudioOnly)
            }
            var analyzerInput: AsyncStream<AnalyzerInput>.Continuation?
            if let (transcriber, _, _) = transcription {
                let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                try await analyzer.start(inputSequence: stream)
                self.analyzer = analyzer
                analyzerInput = continuation
            }
            guard let sink = AudioSink(file: audioFile, input: input, fileFormat: fileFormat, analyzerFormat: transcription?.1, analyzer: analyzerInput) else {
                throw RecorderError.noMicrophone
            }
            sink.install(on: engine.inputNode, format: input)
            engine.prepare()
            try engine.start()

            self.sink = sink
            self.recording = recording
            self.courseId = course
            self.title = title
            self.locale = transcription?.2 ?? locale
            lines = []
            volatile = ""
            bookmarks = []
            elapsed = 0
            state = .recording
            #if os(iOS)
            // A lecture is long; an auto-locked iPad stops the microphone.
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
            if let (transcriber, _, _) = transcription {
                resultsTask = Task { [weak self] in
                    do {
                        for try await result in transcriber.results { self?.take(result) }
                    } catch {}
                }
            }
            clockTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self, let sink = self.sink else { return }
                    self.elapsed = sink.seconds
                    self.level = self.state == .recording ? sink.level : 0
                    // A changed microphone (AirPods, a dock), an interruption or sleep stops the engine without telling
                    // the recording; restart it on the new input.
                    if self.state == .recording, !self.engine.isRunning, Date.now.timeIntervalSince(self.lastRestart) > 1 {
                        self.restartEngine()
                    }
                }
            }
        } catch {
            teardown()
            state = .idle
            throw error
        }
    }

    private enum Transcription {
        case ready(SpeechTranscriber, AVAudioFormat, Locale)
        case downloading, unsupported
    }

    private static func transcriber(for locale: Locale) async -> Transcription {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return .unsupported }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults],
                                            attributeOptions: [.audioTimeRange])
        if await AssetInventory.status(forModules: [transcriber]) != .installed {
            // Downloading can take minutes, which a lecture that is starting doesn't have; it's ready for the next one.
            guard let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return .unsupported }
            Task.detached { try? await request.downloadAndInstall() }
            return .downloading
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { return .unsupported }
        return .ready(transcriber, format, supported)
    }

    private func restartEngine() {
        guard let sink else { return }
        lastRestart = .now
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        let input = engine.inputNode.outputFormat(forBus: 0)
        guard input.sampleRate > 0, sink.retarget(input) else { return }  // no microphone right now; tried again shortly
        sink.install(on: engine.inputNode, format: input)
        engine.prepare()
        try? engine.start()
    }

    func pause() {
        guard state == .recording else { return }
        engine.pause()
        state = .paused
    }

    func resume() throws {
        guard state == .paused else { return }
        try engine.start()
        state = .recording
    }

    func bookmark() {
        guard isActive, var recording else { return }
        bookmarks.append(elapsed)
        recording.bookmarks = bookmarks
        saveProgress(recording)
    }

    func stop() async -> (Recording, LectureTranscript)? {
        guard isActive, var recording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let seconds = sink?.seconds ?? elapsed
        sink?.close()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        if !volatile.isEmpty { lines.append(.init(start: lines.last?.end ?? 0, end: seconds, text: volatile)) }
        recording.duration = seconds
        recording.bookmarks = bookmarks
        let transcript = LectureTranscript(locale: locale.identifier, lines: lines)
        teardown()
        state = .idle
        return (recording, transcript)
    }

    /// For quitting: the audio stays where it is and moves into the course folder at the next launch.
    func stopNow() {
        guard isActive else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sink?.close()
        if let recording, !lines.isEmpty || !volatile.isEmpty {
            let heard = volatile.isEmpty ? lines : lines + [.init(start: lines.last?.end ?? 0, end: elapsed, text: volatile)]
            saveTranscript(recording, LectureTranscript(locale: locale.identifier, lines: heard))
        }
        teardown()
        state = .idle
    }

    private func take(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isFinal {
            volatile = ""
            guard !text.isEmpty else { return }
            lines.append(.init(start: result.range.start.seconds, end: result.range.end.seconds, text: text))
            // Saved as lines settle (at most every few seconds), so a crash keeps what was said.
            if let recording, Date.now.timeIntervalSince(lastTranscriptSave) > 5 {
                lastTranscriptSave = .now
                saveTranscript(recording, LectureTranscript(locale: locale.identifier, lines: lines))
            }
        } else {
            volatile = text
        }
    }

    private func teardown() {
        resultsTask?.cancel()
        clockTask?.cancel()
        resultsTask = nil
        clockTask = nil
        sink = nil
        analyzer = nil
        level = 0
        transcriptionNote = nil
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

enum RecorderError: LocalizedError {
    case microphoneDenied, noMicrophone, localeUnsupported

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: String(localized: .recorderMicrophoneDenied)
        case .noMicrophone: String(localized: .recorderNoMicrophone)
        case .localeUnsupported: String(localized: .recorderLocaleUnsupported)
        }
    }
}

extension LectureRecorder {
    /// Compresses a finished CAF to AAC for the course folder and returns its length. Slow for a long lecture, so it
    /// runs off the main actor.
    nonisolated static func compress(_ source: URL, to target: URL) throws -> TimeInterval {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let output = try AVAudioFile(forWriting: target, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 64_000,
        ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1 << 16) else { throw RecorderError.noMicrophone }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
        }
        // AAC is playable only once closed; it writes its index then.
        output.close()
        return Double(input.length) / format.sampleRate
    }
}

/// Runs on the audio thread: converts each microphone buffer to mono for the file and to the transcriber's format.
/// Not actor-isolated on purpose; a main-actor tap block would trap when the audio thread calls it.
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var toFile: AVAudioConverter
    private var toAnalyzer: AVAudioConverter?
    private let fileFormat: AVAudioFormat
    private let analyzerFormat: AVAudioFormat?
    private let analyzer: AsyncStream<AnalyzerInput>.Continuation?
    private var frames: AVAudioFramePosition = 0
    private var lastLevel: Float = 0

    init?(file: AVAudioFile, input: AVAudioFormat, fileFormat: AVAudioFormat, analyzerFormat: AVAudioFormat?,
          analyzer: AsyncStream<AnalyzerInput>.Continuation?) {
        guard let toFile = AVAudioConverter(from: input, to: fileFormat) else { return nil }
        self.file = file
        self.toFile = toFile
        self.toAnalyzer = analyzerFormat.flatMap { AVAudioConverter(from: input, to: $0) }
        self.fileFormat = fileFormat
        self.analyzerFormat = analyzerFormat
        self.analyzer = analyzer
    }

    /// A new microphone can have another sample rate; the file and the transcriber keep theirs.
    func retarget(_ input: AVAudioFormat) -> Bool {
        lock.withLock {
            guard let converter = AVAudioConverter(from: input, to: fileFormat) else { return false }
            toFile = converter
            toAnalyzer = analyzerFormat.flatMap { AVAudioConverter(from: input, to: $0) }
            return true
        }
    }

    var seconds: TimeInterval { lock.withLock { Double(frames) / fileFormat.sampleRate } }
    var level: Float { lock.withLock { lastLevel } }

    func install(on node: AVAudioInputNode, format: AVAudioFormat) {
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [self] buffer, _ in consume(buffer) }
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let file else { return }
            if let mono = Self.convert(buffer, with: toFile, to: fileFormat) {
                try? file.write(from: mono)
                frames += AVAudioFramePosition(mono.frameLength)
                lastLevel = Self.rms(mono)
            }
            if let toAnalyzer, let analyzerFormat, let converted = Self.convert(buffer, with: toAnalyzer, to: analyzerFormat) {
                analyzer?.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    func close() {
        lock.withLock {
            file?.close()
            file = nil
        }
        analyzer?.finish()
    }

    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }

    /// Loudness for the level meter, 0...1 on a rough dB scale.
    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        let db = 20 * log10(max(sqrt(sum / Float(buffer.frameLength)), 1e-6))
        return max(0, min(1, (db + 55) / 50))
    }
}
