import AVFoundation
import FolioDomain
import Foundation
import Observation
// WhisperKit's classes are not Sendable yet; they are only ever touched inside the actor below.
@preconcurrency import WhisperKit

/// Whisper on this device, for lectures that mix Korean and English: one model hears both, where Apple's recognizer
/// takes one language and turns English terms into Korean sounds. The model is downloaded once per device.
actor WhisperTranscriber {
    static let shared = WhisperTranscriber()
    /// Large v3 Turbo, compressed: Argmax's recommendation for accuracy on Mac and iPad, about 630MB.
    static let variant = "openai_whisper-large-v3-v20240930_626MB"
    static var base: URL { LocalFolders.applicationSupport("Whisper") }
    static var modelFolder: URL { base.appending(path: "models/argmaxinc/whisperkit-coreml/\(variant)", directoryHint: .isDirectory) }

    private var kit: WhisperKit?
    // A transcription awaiting the decoder lets other calls into the actor, so deleting must check it is not mid-run.
    private var running = 0
    private var download: Task<URL, any Error>?

    /// A second caller waits for the same download.
    func prepare(report: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if await WhisperModel.shared.ready {
            if FileManager.default.fileExists(atPath: Self.modelFolder.path) { return Self.modelFolder }
            // Removed outside the app: downloaded again rather than failing every load.
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

    /// Kept in Application Support rather than caches, which the system empties when space runs low and would cost a
    /// 630MB download before the next lecture; but it can always be downloaded again, so it stays out of backups.
    private static func excludeFromBackup() {
        var base = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
    }

    /// `running` and the busy flag it shows count until Whisper actually returns. A cancelled job comes off the queue at
    /// once but holds the model until its current window is decoded.
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

        // Windows are decoded in parallel and report out of order, so progress is the furthest point heard yet.
        let furthest = Furthest()
        kit.segmentDiscoveryCallback = { segments in
            guard let end = segments.map(\.end).max() else { return }
            report(.transcribing(min(furthest.push(Double(end)) / duration, 1)))
        }
        defer { kit.segmentDiscoveryCallback = nil }

        let options = DecodingOptions(
            // Fixed for the whole lecture: left to each 30-second window, a stretch of English terms flips it to English.
            task: .transcribe, language: language,
            // Segment text otherwise carries <|ko|>-style tokens.
            skipSpecialTokens: true,
            promptTokens: hints.flatMap { promptTokens($0, in: kit) },
            // Cuts the audio at silences, so a long quiet stretch doesn't make Whisper invent a sentence.
            chunkingStrategy: .vad)
        // A lecture read whole is several hundred megabytes of samples; streamed, a few.
        let results = try await kit.transcribe(
            audioPath: url.path, audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
            decodeOptions: options)
        // With silence chunking a cancelled run returns what it had instead of throwing.
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

    /// Korean or English, by three windows across the lecture: the opening minutes are often small talk or silence.
    /// Korean when unsure, since a Korean lecture with English terms is the common case and Korean decoding keeps them.
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

    /// Whisper reads the prompt as what was said just before, so it writes the slides' terms in their own spelling.
    /// It keeps the last 224 tokens of a prompt; the least telling terms go first to stay well under that.
    private func promptTokens(_ hints: TranscriptionHints, in kit: WhisperKit) -> [Int]? {
        guard let tokenizer = kit.tokenizer else { return nil }
        var count = hints.terms.count
        while true {
            let tokens = tokenizer.encode(text: " " + hints.prompt(terms: count)).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            if tokens.count <= 150 || count == 0 { return tokens }
            count -= max(1, count / 8)
        }
    }

    /// Whisper fills a pause with a line it saw often in training, the close of a video. Its scores rate it as sure as
    /// the speech around it, and the segment's span takes in the end of that speech, so its loudness gives it away
    /// neither; only the words do. A lecture's own lone "감사합니다." is lost with them.
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
        // Core ML compiles the model for this chip on the first load, minutes on end; later loads take seconds.
        report(.preparing)
        // The tokenizer comes from the network on the first load and is kept beside the model.
        let kit = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: folder.path, tokenizerFolder: Self.base, verbose: false,
                prewarm: false, load: true, download: false))
        self.kit = kit
        return kit
    }

    /// Settings disables deleting while `busy`; this refuses too, for a job that starts in between.
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

/// Whether this device has the Whisper model, for settings and the player. Remembered rather than looked up: a
/// download cut off halfway leaves a folder that looks the same.
@MainActor @Observable
final class WhisperModel {
    static let shared = WhisperModel()
    private static let readyKey = "folio.whisperModelReady"

    private(set) var ready = UserDefaults.standard.bool(forKey: readyKey)
    /// 0...1 while the model downloads.
    fileprivate(set) var downloading: Double?
    /// Whisper is transcribing with the model, which then can't be deleted.
    fileprivate(set) var busy = false
    private(set) var failure: String?

    fileprivate func finishDownload(ready: Bool) {
        self.ready = ready
        downloading = nil
        // A failed download sets its reason after this, so success and deletion both clear an old one.
        failure = nil
        UserDefaults.standard.set(ready, forKey: Self.readyKey)
    }

    func download() {
        failure = nil
        Task {
            do { _ = try await WhisperTranscriber.shared.prepare { _ in } } catch {
                failure = String(localized: .settingsWhisperDownloadFailed(error.localizedDescription))
            }
        }
    }

    func delete() {
        Task { await WhisperTranscriber.shared.deleteModel() }
    }
}
