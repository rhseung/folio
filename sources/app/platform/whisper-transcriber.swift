import AVFoundation
import FolioDomain
import Foundation
import Observation
// WhisperKit의 클래스는 아직 Sendable이 아니다. 아래 actor 안에서만 다룬다.
@preconcurrency import WhisperKit

actor WhisperTranscriber {
    static let shared = WhisperTranscriber()
    static let variant = "openai_whisper-large-v3-v20240930_626MB"
    static var base: URL { LocalFolders.applicationSupport("Whisper") }
    static var modelFolder: URL { base.appending(path: "models/argmaxinc/whisperkit-coreml/\(variant)", directoryHint: .isDirectory) }

    private var kit: WhisperKit?
    // 디코더를 기다리는 받아쓰기는 actor에 다른 호출을 들여보내므로, 삭제는 실행 중이 아닌지 확인해야 한다.
    private var running = 0
    private var download: Task<URL, any Error>?

    func prepare(report: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if await WhisperModel.shared.ready {
            if FileManager.default.fileExists(atPath: Self.modelFolder.path) { return Self.modelFolder }
            await MainActor.run { WhisperModel.shared.finishDownload(ready: false) }
        }
        if let download { return try await download.value }
        let task = Task {
            try await WhisperKit.download(variant: Self.variant, downloadBase: Self.base) { progress in
                let fraction = progress.fractionCompleted
                report(fraction)
                Task { @MainActor in WhisperModel.shared.downloading = fraction }
            }
        }
        download = task
        await MainActor.run { WhisperModel.shared.downloading = 0 }
        defer { download = nil }
        do {
            let folder = try await task.value
            Self.excludeFromBackup()
            await MainActor.run { WhisperModel.shared.finishDownload(ready: true) }
            return folder
        } catch {
            await MainActor.run { WhisperModel.shared.finishDownload(ready: false) }
            throw error
        }
    }

    // 캐시가 아니라 Application Support에 둔다. 시스템은 공간이 부족하면 캐시를 비우고, 그러면 다음 강의 전에 630MB를 다시 내려받아야 한다. 다만 언제든 다시 내려받을 수 있으므로
    // 백업에서는 뺀다.
    private static func excludeFromBackup() {
        var base = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
    }

    func transcribe(_ url: URL, hints: TranscriptionHints?, report: @escaping @Sendable (TranscriptionPhase) -> Void) async throws
        -> LectureTranscript
    {
        running += 1
        await showBusy()
        do {
            let transcript = try await run(url, hints: hints, report: report)
            running -= 1
            await showBusy()
            return transcript
        } catch {
            running -= 1
            await showBusy()
            throw error
        }
    }

    private func showBusy() async {
        let busy = running > 0
        await MainActor.run { WhisperModel.shared.busy = busy }
    }

    private func run(_ url: URL, hints: TranscriptionHints?, report: @escaping @Sendable (TranscriptionPhase) -> Void) async throws
        -> LectureTranscript
    {
        let kit = try await load(report: report)
        let duration = (try? AVAudioFile(forReading: url)).map { max(Double($0.length) / $0.processingFormat.sampleRate, 1) } ?? 1
        report(.transcribing(0))
        let language = try await language(of: url, duration: duration, in: kit)

        let furthest = Furthest()
        kit.segmentDiscoveryCallback = { segments in
            guard let end = segments.map(\.end).max() else { return }
            report(.transcribing(min(furthest.push(Double(end)) / duration, 1)))
        }
        defer { kit.segmentDiscoveryCallback = nil }

        let options = DecodingOptions(
            // 강의 전체에 하나로 고정한다. 30초 구간마다 정하게 두면 영어 용어가 이어지는 부분에서 영어로 바뀐다.
            task: .transcribe, language: language,
            skipSpecialTokens: true,
            promptTokens: hints.flatMap { promptTokens($0, in: kit) },
            // 오디오를 침묵에서 자른다. 그래야 긴 침묵에서 Whisper가 문장을 지어내지 않는다.
            chunkingStrategy: .vad)
        let results = try await kit.transcribe(
            audioPath: url.path, audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
            decodeOptions: options)
        // 침묵 단위로 자르면 취소한 실행이 오류를 던지지 않고 그때까지의 결과를 돌려준다.
        try Task.checkCancellation()

        let lines = results.flatMap(\.segments)
            .sorted { $0.start < $1.start }
            .compactMap { s -> LectureTranscript.Line? in
                let text = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !Self.isFiller(text) else { return nil }
                return .init(start: Double(s.start), end: Double(s.end), text: text)
            }
        return LectureTranscript(locale: language == "en" ? "en-US" : "ko-KR", lines: lines)
    }

    private func language(of url: URL, duration: Double, in kit: WhisperKit) async throws -> String {
        var english = 0, korean = 0
        for at in [0.2, 0.5, 0.8] {
            let start = max(0, duration * at - 15)
            guard let buffer = try? AudioProcessor.loadAudio(fromPath: url.path, startTime: start, endTime: min(duration, start + 30)),
                let result = try? await kit.detectLangauge(audioArray: AudioProcessor.convertBufferToArray(buffer: buffer))
            else { continue }
            let ko = result.langProbs["ko"] ?? -.infinity, en = result.langProbs["en"] ?? -.infinity
            if en > ko { english += 1 } else { korean += 1 }
        }
        try Task.checkCancellation()
        return english > korean ? "en" : "ko"
    }

    // Whisper는 프롬프트를 바로 앞에서 한 말로 읽으므로, 슬라이드의 용어를 원래 철자로 적는다. Whisper는 프롬프트의 마지막 224 토큰만 남기므로, 그 한도에 여유 있게 들도록 덜 중요한 용어부터
    // 뺀다.
    private func promptTokens(_ hints: TranscriptionHints, in kit: WhisperKit) -> [Int]? {
        guard let tokenizer = kit.tokenizer else { return nil }
        var count = hints.terms.count
        while true {
            let tokens = tokenizer.encode(text: " " + hints.prompt(terms: count)).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            if tokens.count <= 150 || count == 0 { return tokens }
            count -= max(1, count / 8)
        }
    }

    // Whisper는 쉬는 구간을 학습 때 자주 본 문장, 즉 영상의 맺음말로 채운다. 그 점수는 주변 말소리만큼 확실하게 나오고, 세그먼트 구간이 앞 말소리의 끝을 포함하므로 소리 크기로도 가려낼 수 없다.
    // 낱말로만 가려낼 수 있다. 그래서 강의에서 실제로 홀로 말한 "감사합니다."도 함께 사라진다.
    static func isFiller(_ text: String) -> Bool {
        let bare = text.lowercased().filter { $0.isLetter }
        return fillers.contains(bare)
    }

    private static let fillers: Set<String> = [  // strings: data, matched against transcripts
        "감사합니다", "시청해주셔서감사합니다", "시청해주셔서고맙습니다", "구독과좋아요부탁드립니다", "구독과좋아요알림설정부탁드립니다",
        "thankyou", "thanksforwatching", "thankyouforwatching", "pleasesubscribe",
    ]

    private func load(report: @escaping @Sendable (TranscriptionPhase) -> Void) async throws -> WhisperKit {
        if let kit { return kit }
        let folder = try await prepare { report(.downloading($0)) }
        report(.preparing)
        let kit = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: folder.path, tokenizerFolder: Self.base, verbose: false,
                prewarm: false, load: true, download: false))
        self.kit = kit
        return kit
    }

    func deleteModel() async {
        guard running == 0 else { return }
        download?.cancel()
        await kit?.unloadModels()
        kit = nil
        // folio:not-an-action the model lives in this device's Application Support, outside the GIST folder
        try? FileManager.default.removeItem(at: Self.base)
        await MainActor.run { WhisperModel.shared.finishDownload(ready: false) }
    }
}

private final class Furthest: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func push(_ v: Double) -> Double {
        lock.withLock {
            value = max(value, v); return value
        }
    }
}
