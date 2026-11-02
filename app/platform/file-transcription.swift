import AVFoundation
import FolioDomain
import Speech

/// What turns a finished recording into text. Per device, not in settings.json: the Whisper model lives on this device.
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case apple, whisper
    var id: Self { self }
    static let storageKey = "folio.transcriptionEngine"

    static var preferred: TranscriptionEngine {
        UserDefaults.standard.string(forKey: storageKey).flatMap(TranscriptionEngine.init) ?? .standard
    }

    static let standard = TranscriptionEngine.whisper

    /// `locale` is a guess (the live captions' language) that only Apple's recognizer needs; Whisper listens for itself.
    /// Without `mayDownload` Whisper stands in only if its model is here: 630MB is downloaded when someone asked.
    func transcribe(_ url: URL, locale: Locale, hints: TranscriptionHints?, mayDownload: Bool,
                    report: @escaping @Sendable (TranscriptionPhase) -> Void) async throws -> LectureTranscript {
        switch self {
        case .apple:
            do {
                return try await AppleFileTranscriber.transcribe(url, locale: locale, hints: hints, report: report)
            } catch TranscriptionError.localeUnsupported where mayDownload {
                // A recording must never be left without a transcript; Whisper hears every language Folio records in.
                return try await WhisperTranscriber.shared.transcribe(url, hints: hints, report: report)
            }
        case .whisper:
            return try await WhisperTranscriber.shared.transcribe(url, hints: hints, report: report)
        }
    }
}

enum TranscriptionPhase: Equatable, Sendable {
    /// Behind another recording: one model at a time, since Whisper's alone takes a gigabyte of memory.
    case waiting
    case downloading(Double)
    /// Loading a downloaded model, which the first time on a device takes minutes.
    case preparing
    case transcribing(Double)
}

enum TranscriptionError: LocalizedError {
    case localeUnsupported, unreadableAudio

    var errorDescription: String? {
        switch self {
        case .localeUnsupported: String(localized: .recordingErrorLocaleUnsupported)
        case .unreadableAudio: String(localized: .recordingErrorUnreadableAudio)
        }
    }
}

/// The same recognizer as the live captions, run over the whole file. Unlike a lecture that is starting, this can wait
/// for the language model to download.
enum AppleFileTranscriber {
    static func transcribe(_ url: URL, locale: Locale, hints: TranscriptionHints?, report: @escaping @Sendable (TranscriptionPhase) -> Void) async throws -> LectureTranscript {
        guard SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.localeUnsupported
        }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let request = try await SpeechAssets.request(for: transcriber, locale: supported) {
            let progress = request.progress
            let watch = Task {
                while !Task.isCancelled {
                    report(.downloading(progress.fractionCompleted))
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { watch.cancel() }
            try await request.downloadAndInstall()
        }
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else { throw TranscriptionError.localeUnsupported }
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw TranscriptionError.unreadableAudio }
        let duration = max(Double(file.length) / file.processingFormat.sampleRate, 1)
        report(.transcribing(0))

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if let hints { try await analyzer.setContext(SpeechAssets.context(hints)) }
        return try await withTaskCancellationHandler {
            async let lines = collect(transcriber, duration: duration, report: report)
            if let end = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return LectureTranscript(locale: supported.identifier, lines: try await lines)
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private static func collect(_ transcriber: SpeechTranscriber, duration: TimeInterval,
                                report: @Sendable (TranscriptionPhase) -> Void) async throws -> [LectureTranscript.Line] {
        var lines: [LectureTranscript.Line] = []
        for try await result in transcriber.results where result.isFinal {
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            lines.append(.init(start: result.range.start.seconds, end: result.range.end.seconds, text: text))
            report(.transcribing(min(result.range.end.seconds / duration, 1)))
        }
        return lines
    }
}

enum SpeechAssets {
    /// What still has to download before `transcriber` runs, or nil when it is ready. An app sees a language model only
    /// after reserving its locale, even one another app already installed; until then its status reads as not
    /// installed and asking to install it returns nothing, which once read as "this language can't be transcribed".
    static func request(for transcriber: SpeechTranscriber, locale: Locale) async throws -> AssetInstallationRequest? {
        try await reserve(locale)
        guard await AssetInventory.status(forModules: [transcriber]) != .installed else { return nil }
        return try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
    }

    /// The slides' terms, which the recognizer then prefers over words that sound alike.
    static func context(_ hints: TranscriptionHints) -> AnalysisContext {
        let context = AnalysisContext()
        context.contextualStrings[.general] = hints.terms
        return context
    }

    /// An app holds a few locales at most; the one needed now takes the place of another.
    private static func reserve(_ locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        if reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) { return }
        if reserved.count >= AssetInventory.maximumReservedLocales, let other = reserved.first {
            _ = await AssetInventory.release(reservedLocale: other)
        }
        _ = try await AssetInventory.reserve(locale: locale)
    }
}
