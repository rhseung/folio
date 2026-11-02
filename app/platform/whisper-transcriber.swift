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
    static let base = URL.applicationSupportDirectory.appending(path: "Folio/Whisper", directoryHint: .isDirectory)
    static var modelFolder: URL { base.appending(path: "models/argmaxinc/whisperkit-coreml/\(variant)", directoryHint: .isDirectory) }

    private var kit: WhisperKit?
    private var download: Task<URL, any Error>?

    /// Downloads the model if this device doesn't have it. A second caller waits for the same download.
    func prepare(report: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if await WhisperModel.shared.ready { return Self.modelFolder }
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
            await MainActor.run { WhisperModel.shared.finishDownload(ready: true) }
            return folder
        } catch {
            await MainActor.run { WhisperModel.shared.finishDownload(ready: false) }
            throw error
        }
    }

    func transcribe(_ url: URL, locale: Locale, report: @escaping @Sendable (TranscriptionPhase) -> Void) async throws -> LectureTranscript {
        let kit = try await load(report: report)
        let duration = (try? AVAudioFile(forReading: url)).map { max(Double($0.length) / $0.processingFormat.sampleRate, 1) } ?? 1
        report(.transcribing(0))
        // Windows are decoded in parallel and report out of order, so progress is the furthest point heard yet.
        let furthest = Furthest()
        kit.segmentDiscoveryCallback = { segments in
            guard let end = segments.map(\.end).max() else { return }
            report(.transcribing(min(furthest.push(Double(end)) / duration, 1)))
        }
        defer { kit.segmentDiscoveryCallback = nil }
        let options = DecodingOptions(
            // The language picked when recording: with none, Whisper's prompt assumes English.
            task: .transcribe, language: locale.language.languageCode?.identifier ?? "ko",
            // Segment text otherwise carries <|ko|>-style tokens.
            skipSpecialTokens: true,
            // Cuts the audio at silences, so a long quiet stretch doesn't make Whisper invent a sentence.
            chunkingStrategy: .vad)
        // A lecture read whole is several hundred megabytes of samples; streamed, a few.
        let results = try await kit.transcribe(audioPath: url.path, audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
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
        return LectureTranscript(locale: locale.identifier, lines: lines)
    }

    /// Whisper fills a pause with a line it saw often in training, the close of a video. Its scores rate it as sure as
    /// the speech around it, and the segment's span takes in the end of that speech, so its loudness gives it away
    /// neither; only the words do. A lecture's own lone "감사합니다." is lost with them.
    static func isFiller(_ text: String) -> Bool {
        let bare = text.lowercased().filter { $0.isLetter }
        return fillers.contains(bare)
    }

    private static let fillers: Set<String> = [
        "감사합니다", "시청해주셔서감사합니다", "시청해주셔서고맙습니다", "구독과좋아요부탁드립니다", "구독과좋아요알림설정부탁드립니다",
        "thankyou", "thanksforwatching", "thankyouforwatching", "pleasesubscribe",
    ]

    private func load(report: @escaping @Sendable (TranscriptionPhase) -> Void) async throws -> WhisperKit {
        if let kit { return kit }
        let folder = try await prepare { report(.downloading($0)) }
        // Core ML compiles the model for this chip on the first load, minutes on end; later loads take seconds.
        report(.preparing)
        // The tokenizer comes from the network on the first load and is kept beside the model.
        let kit = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, tokenizerFolder: Self.base, verbose: false,
                                                        prewarm: false, load: true, download: false))
        self.kit = kit
        return kit
    }

    /// Frees the gigabyte the loaded model holds, and with `delete` the model files.
    func unload(delete: Bool) async {
        download?.cancel()
        await kit?.unloadModels()
        kit = nil
        if delete {
            // folio:not-an-action the model lives in this device's Application Support, outside the GIST folder
            try? FileManager.default.removeItem(at: Self.base)
            await MainActor.run { WhisperModel.shared.finishDownload(ready: false) }
        }
    }
}

private final class Furthest: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func push(_ v: Double) -> Double { lock.withLock { value = max(value, v); return value } }
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

    fileprivate func finishDownload(ready: Bool) {
        self.ready = ready
        downloading = nil
        UserDefaults.standard.set(ready, forKey: Self.readyKey)
    }

    func download() {
        Task { _ = try? await WhisperTranscriber.shared.prepare { _ in } }
    }

    func delete() {
        Task { await WhisperTranscriber.shared.unload(delete: true) }
    }
}
