import AVFoundation
import FolioDomain
import Speech

#if os(iOS)
import UIKit
#endif

@MainActor @Observable
final class LectureRecorder {
    // `stopping`은 받아쓰기가 끝날 때까지 몇 초 이어진다. 이 상태가 없을 때는 그사이 다시 멈추면 마지막 말이 두 번
    // 붙었다.
    enum State { case idle, preparing, recording, paused, stopping }

    private(set) var state = State.idle
    private(set) var courseId: UUID?
    private(set) var recording: Recording?
    private(set) var title = ""
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    private(set) var lines: [LectureTranscript.Line] = []
    private(set) var volatile = ""
    private(set) var bookmarks: [TimeInterval] = []
    private(set) var pages: [PageVisit] = []
    private(set) var context: TranscriptionContext?
    private(set) var locale = Locale(identifier: "ko-KR")
    private(set) var transcriptionNote: String?

    // 시작, 재개, 장치 변경마다 engine을 새로 만든다. 오래 쓴 engine은 처음 본 마이크의 형식(AirPods의 24kHz)을
    // 하드웨어가 48kHz로 돌아간 뒤에도 유지했고, 그 engine에 tap을 걸면 아무것도 녹음되지 않거나 앱이 비정상 종료되었다.
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var engineObserver: NSObjectProtocol?
    @ObservationIgnored private var heardBuffers = 0
    @ObservationIgnored private var lastHeard = Date.distantPast
    @ObservationIgnored private var sink: AudioSink?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var lastTranscriptSave = Date.distantPast
    @ObservationIgnored var saveTranscript: (Recording, LectureTranscript) -> Void = { _, _ in }
    @ObservationIgnored var saveProgress: (Recording) -> Void = { _ in }
    @ObservationIgnored private var lastRestart = Date.distantPast

    var isActive: Bool { state != .idle }
    // `recording`은 녹음이 끝난 뒤에도 남아, 사이드바 카드가 사라지는 동안 과목과 회차를 계속 보인다. 그 값으로 판단하던
    // 때는 끝난 녹음을 진행 중으로 읽어 삭제가 거절되었다. 이 값은 준비를 시작한 순간부터 새 녹음을 가리킨다. 그렇지 않을
    // 때는 복구가 새 녹음의 빈 파일을 비정상 종료가 남긴 파일로 보고 과목 폴더로 옮겼고, 강의는 삭제된 파일에 계속
    // 녹음되었다.
    var current: UUID? { isActive ? recording?.id : nil }

    private var running: Bool { state == .recording || state == .paused }
    var capturing: UUID? { running ? recording?.id : nil }

    // 이 기기에 압축하지 않은 CAF로 녹음한다. AAC와 달리 녹음 중에 앱이 종료되어도 마지막 buffer까지 읽을 수 있다.
    // 받아쓰기는 가능한 만큼만 하고, 오디오는 받아쓰기를 기다리지 않는다.
    func start(_ recording: Recording, at file: URL, course: UUID, title: String, locale: Locale) async throws {
        guard state == .idle else { return }
        state = .preparing
        self.recording = recording
        courseId = course
        self.title = title
        lines = []
        volatile = ""
        bookmarks = []
        pages = []
        context = nil
        elapsed = 0

        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.microphoneDenied }
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif

            var transcription: (SpeechTranscriber, AVAudioFormat, Locale)?
            switch await Self.transcriber(for: locale) {
            case .ready(let t, let format, let supported): transcription = (t, format, supported)
            case .downloading: transcriptionNote = String(localized: .recordingNoteDownloading)
            case .unsupported: transcriptionNote = String(localized: .recordingNoteUnsupported)
            }
            var analyzerInput: AsyncStream<AnalyzerInput>.Continuation?
            if let (transcriber, _, _) = transcription {
                let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                try await analyzer.start(inputSequence: stream)
                self.analyzer = analyzer
                analyzerInput = continuation
            }

            // 마이크 형식은 위의 대기가 끝난 지금 읽는다. 대기 중에 장치가 바뀔 수 있고, 그 전에 읽은 형식으로 tap을 걸면
            // Objective-C 예외가 나서 앱이 종료된다.
            guard let (engine, input) = Self.tappableEngine(),
                let fileFormat = AVAudioFormat(standardFormatWithSampleRate: input.sampleRate, channels: 1)
            else {
                analyzerInput?.finish()
                throw RecorderError.noMicrophone
            }
            let audioFile = try AVAudioFile(
                forWriting: file,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: input.sampleRate, AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                ], commonFormat: .pcmFormatFloat32, interleaved: false)
            guard
                let sink = AudioSink(
                    file: audioFile, input: input, fileFormat: fileFormat, analyzerFormat: transcription?.1, analyzer: analyzerInput)
            else {
                analyzerInput?.finish()
                throw RecorderError.noMicrophone
            }
            self.sink = sink
            lastRestart = .now
            try run(engine, tapping: input, into: sink)
            try await waitForSignal(sink)

            self.locale = transcription?.2 ?? locale
            state = .recording
            #if os(iOS)
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
                    guard !Task.isCancelled, let self, let sink = self.sink else { return }
                    self.elapsed = sink.seconds
                    self.level = self.state == .recording ? LectureLoudness.level(sink.takeDecibels()) : 0
                    let buffers = sink.buffers
                    if buffers != self.heardBuffers {
                        self.heardBuffers = buffers
                        self.lastHeard = .now
                    }
                    // configuration change 알림을 보완한다. 중단이나 잠자기는 알림 없이 engine을 멈출 수 있고, 변경이 대기 중일 때 건
                    // tap은 소리 없이 계속 돈다.
                    let now = Date.now
                    if self.state == .recording,
                        MicrophoneTap.restartDue(
                            running: self.engine?.isRunning ?? false,
                            sinceHeard: now.timeIntervalSince(max(self.lastHeard, self.lastRestart)),
                            sinceRestart: now.timeIntervalSince(self.lastRestart))
                    {
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
        guard SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return .unsupported
        }
        let transcriber = SpeechTranscriber(
            locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange])
        do {
            if let request = try await SpeechAssets.request(for: transcriber, locale: supported) {
                Task.detached { try? await request.downloadAndInstall() }
                return .downloading
            }
        } catch {
            return .unsupported
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { return .unsupported }
        return .ready(transcriber, format, supported)
    }

    // 장치가 바뀌는 중에는 새 engine도 이전 rate를 읽을 수 있다. 그래서 한 번 더 만들어 보고, 그래도 안 되면 호출한 쪽이
    // 나중에 다시 시도한다.
    private static func tappableEngine() -> (AVAudioEngine, AVAudioFormat)? {
        for _ in 0..<2 {
            let engine = AVAudioEngine()
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            switch MicrophoneTap.plan(hardware: .init(node.inputFormat(forBus: 0)), node: .init(format)) {
            case .tap: return (engine, format)
            case .rebuild: continue
            case .noInput: return nil
            }
        }
        return nil
    }

    private func run(_ engine: AVAudioEngine, tapping format: AVAudioFormat, into sink: AudioSink) throws {
        self.engine = engine
        engineObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.engineChanged() }
        }
        sink.install(on: engine.inputNode, format: format)
        engine.prepare()
        try engine.start()
    }

    private func engineChanged() {
        guard state == .recording || state == .preparing else { return }
        restartEngine()
    }

    // 시작할 때 tap을 걸고 engine을 돌려도 소리가 들어오지 않을 수 있다("Failed to create tap, config change pending!").
    // 그렇게 녹음한 강의는 끝까지 무음이었으므로, 이때는 시작을 실패로 처리한다.
    private func waitForSignal(_ sink: AudioSink) async throws {
        for attempt in 0..<2 {
            let deadline = ContinuousClock.now + .seconds(MicrophoneTap.stall)
            while ContinuousClock.now < deadline {
                if sink.buffers > 0 { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            if attempt == 0 { restartEngine() }
        }
        throw RecorderError.noSignal
    }

    @discardableResult
    private func restartEngine() -> Bool {
        guard let sink else { return false }
        lastRestart = .now
        retireEngine()
        guard let (engine, input) = Self.tappableEngine(), sink.retarget(input) else { return false }
        do {
            try run(engine, tapping: input, into: sink)
            return true
        } catch {
            retireEngine()
            return false
        }
    }

    func pause() {
        guard state == .recording else { return }
        engine?.pause()
        state = .paused
    }

    func resume() throws {
        guard state == .paused else { return }
        guard restartEngine() else { throw RecorderError.noMicrophone }
        state = .recording
    }

    var snapshot: Recording? {
        guard running, var recording else { return nil }
        recording.duration = elapsed
        recording.bookmarks = bookmarks
        recording.pages = pages
        return recording
    }

    func bookmark() {
        guard running else { return }
        bookmarks.append(elapsed)
        if let snapshot { saveProgress(snapshot) }
    }

    func show(_ material: UUID, page: Int?) {
        guard let snapshot, let visit = snapshot.visit(material, page: page, at: elapsed) else { return }
        pages.append(visit)
        if let latest = self.snapshot { saveProgress(latest) }
    }

    func stop() async -> (Recording, LectureTranscript)? {
        guard running, var recording else { return nil }
        state = .stopping
        stopEngine()
        let seconds = sink?.seconds ?? elapsed
        sink?.close()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        if !volatile.isEmpty { lines.append(.init(start: lines.last?.end ?? 0, end: seconds, text: volatile)) }
        recording.duration = seconds
        recording.bookmarks = bookmarks
        recording.pages = pages
        let transcript = LectureTranscript(locale: locale.identifier, lines: lines, context: context)
        teardown()
        state = .idle
        return (recording, transcript)
    }

    func stopNow() {
        guard isActive else { return }
        stopEngine()
        sink?.close()
        if let recording, !lines.isEmpty || !volatile.isEmpty {
            let heard = volatile.isEmpty ? lines : lines + [.init(start: lines.last?.end ?? 0, end: elapsed, text: volatile)]
            saveTranscript(recording, LectureTranscript(locale: locale.identifier, lines: heard, context: context))
        }
        teardown()
        state = .idle
    }

    #if DEBUG
    func stage(_ recording: Recording, course: UUID, title: String, paused: Bool = false, level: Float = 0.6) {
        courseId = course
        self.recording = recording
        self.title = title
        state = paused ? .paused : .recording
        elapsed = 2951
        self.level = paused ? 0 : level
        bookmarks = [612]
        lines = [
            .init(start: 2890, end: 2912, text: "그래서 이 문법은 모호하지 않다는 걸 보이려면 유도 트리가 하나뿐이라는 걸 보여야 하고요"),
            .init(start: 2912, end: 2934, text: "왼쪽 재귀를 없애는 방법은 지난 시간에 본 것처럼 새 비단말을 하나 도입하는 겁니다"),
        ]
        volatile = "이제 이걸 LL(1) 파싱 표로 옮겨 보면"
    }
    #endif

    private func take(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isFinal {
            volatile = ""
            guard !text.isEmpty else { return }
            lines.append(.init(start: result.range.start.seconds, end: result.range.end.seconds, text: text))
            if let recording, Date.now.timeIntervalSince(lastTranscriptSave) > 5 {
                lastTranscriptSave = .now
                saveTranscript(recording, LectureTranscript(locale: locale.identifier, lines: lines, context: context))
            }
        } else {
            volatile = text
        }
    }

    func use(_ context: TranscriptionContext, hints: TranscriptionHints, for recording: UUID, telling: Int) async {
        guard current == recording, telling == tellings else { return }
        self.context = context
        guard let analyzer else { return }
        try? await analyzer.setContext(SpeechAssets.context(hints))
    }

    // 내려받기 때문에 앞선 읽기가 뒤의 읽기보다 늦게 끝날 수 있고, 그러면 범위가 좁은 쪽이 자막에 준 값을 덮어쓴다.
    // 그래서 읽기마다 번호를 매긴다.
    func telling() -> Int {
        tellings += 1
        return tellings
    }

    @ObservationIgnored private var tellings = 0

    // 시계를 먼저 멈춘다. 시계는 멈춘 engine을 보면 다시 켜고, 멈추기는 받아쓰기를 몇 초 기다린다. 그사이 시계가 새 tap으로
    // 마이크를 다시 켰고, 같은 bus에 다음 녹음이 tap을 걸면 앱이 비정상 종료되었다. 시계가 음량도 낮췄으므로 여기서 0으로
    // 두어야 그 몇 초 동안 카드가 빛나지 않는다.
    private func stopEngine() {
        clockTask?.cancel()
        clockTask = nil
        level = 0
        retireEngine()
    }

    private func retireEngine() {
        if let engineObserver { NotificationCenter.default.removeObserver(engineObserver) }
        engineObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func teardown() {
        stopEngine()
        resultsTask?.cancel()
        resultsTask = nil
        sink = nil
        analyzer = nil
        transcriptionNote = nil
        context = nil
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

enum RecorderError: LocalizedError {
    case microphoneDenied, noMicrophone, noSignal, localeUnsupported

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: String(localized: .recordingErrorMicrophoneDenied)
        case .noMicrophone: String(localized: .recordingErrorNoMicrophone)
        case .noSignal: String(localized: .recordingErrorNoSignal)
        case .localeUnsupported: String(localized: .recordingErrorLocaleUnsupported)
        }
    }
}

extension LectureRecorder {
    nonisolated static func compress(_ source: URL, to target: URL) throws -> TimeInterval {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let output = try AVAudioFile(
            forWriting: target,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 64_000,
            ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1 << 16) else { throw RecorderError.noMicrophone }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
        }
        // AAC는 닫을 때 색인을 쓰므로, 닫은 뒤에야 재생할 수 있다.
        output.close()
        return Double(input.length) / format.sampleRate
    }
}

// audio thread에서 실행되므로 일부러 actor에 격리하지 않는다. main actor의 tap block은 audio thread가 부르면 trap이
// 난다.
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var toFile: AVAudioConverter
    private var toAnalyzer: AVAudioConverter?
    private let fileFormat: AVAudioFormat
    private let analyzerFormat: AVAudioFormat?
    private let analyzer: AsyncStream<AnalyzerInput>.Continuation?
    private var frames: AVAudioFramePosition = 0
    private var received = 0
    private var energy: Float = 0
    private var energyFrames = 0

    init?(
        file: AVAudioFile, input: AVAudioFormat, fileFormat: AVAudioFormat, analyzerFormat: AVAudioFormat?,
        analyzer: AsyncStream<AnalyzerInput>.Continuation?
    ) {
        guard let toFile = AVAudioConverter(from: input, to: fileFormat) else { return nil }
        self.file = file
        self.toFile = toFile
        self.toAnalyzer = analyzerFormat.flatMap { AVAudioConverter(from: input, to: $0) }
        self.fileFormat = fileFormat
        self.analyzerFormat = analyzerFormat
        self.analyzer = analyzer
    }

    func retarget(_ input: AVAudioFormat) -> Bool {
        lock.withLock {
            guard let converter = AVAudioConverter(from: input, to: fileFormat) else { return false }
            toFile = converter
            toAnalyzer = analyzerFormat.flatMap { AVAudioConverter(from: input, to: $0) }
            return true
        }
    }

    var seconds: TimeInterval { lock.withLock { Double(frames) / fileFormat.sampleRate } }
    var buffers: Int { lock.withLock { received } }
    func takeDecibels() -> Float {
        lock.withLock {
            defer { energy = 0; energyFrames = 0 }
            return energyFrames == 0 ? -120 : 10 * log10(max(energy / Float(energyFrames), 1e-12))
        }
    }

    func install(on node: AVAudioInputNode, format: AVAudioFormat) {
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [self] buffer, _ in consume(buffer) }
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            received += 1
            guard let file else { return }
            if let mono = Self.convert(buffer, with: toFile, to: fileFormat) {
                try? file.write(from: mono)
                frames += AVAudioFramePosition(mono.frameLength)
                energy += Self.sumOfSquares(mono)
                energyFrames += Int(mono.frameLength)
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

    static func sumOfSquares(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return sum
    }
}

// input node는 sample rate를 변환하지 못한다. 하드웨어와 다른 rate를 읽는 동안 tap을 걸면 아무것도 녹음되지
// 않거나("config change pending") Objective-C 예외가 난다(`installTapOnBus` "Format mismatch: input hw 48000 Hz,
// client 24000 Hz"). Swift는 이 예외를 잡지 못하므로 앱이 종료된다.
enum MicrophoneTap {
    struct Stream: Equatable {
        var sampleRate: Double
        var channels: UInt32
    }

    enum Plan: Equatable { case tap, rebuild, noInput }

    static let stall: TimeInterval = 2
    static let settle: TimeInterval = 1

    static func plan(hardware: Stream, node: Stream) -> Plan {
        guard hardware.sampleRate > 0, hardware.channels > 0 else { return .noInput }
        return node.sampleRate == hardware.sampleRate && node.channels > 0 ? .tap : .rebuild
    }

    static func restartDue(running: Bool, sinceHeard: TimeInterval, sinceRestart: TimeInterval) -> Bool {
        sinceRestart > settle && (!running || sinceHeard > stall)
    }
}

extension MicrophoneTap.Stream {
    init(_ format: AVAudioFormat) {
        self.init(sampleRate: format.sampleRate, channels: format.channelCount)
    }
}

// 범위는 책상 위 노트북이 듣는 수업 소리를 기준으로, 녹음한 강의를 1초 단위로 잰 값이다. -57dB는 문장 사이의 교실
// 소리(10번째 백분위수)이고, -42dB는 강의자가 목소리를 높일 때(95번째 백분위수)다. 예전의 -55dB에서 -5dB까지의
// 범위에서는 수업 전체가 눈금의 3분의 1 아래에 머물러, 미터와 카드의 빛이 거의 움직이지 않았다.
enum LectureLoudness {
    static let quiet: Float = -57
    static let loud: Float = -42

    static func level(_ decibels: Float) -> Float {
        max(0, min(1, (decibels - quiet) / (loud - quiet)))
    }
}
