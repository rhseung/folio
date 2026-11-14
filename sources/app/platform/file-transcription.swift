import AVFoundation
import FolioDomain
import Speech

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case apple, whisper
    var id: Self { self }
    static let storageKey = "folio.transcriptionEngine"

    static var preferred: TranscriptionEngine {
        UserDefaults.standard.string(forKey: storageKey).flatMap(TranscriptionEngine.init) ?? .standard
    }

    static let standard = TranscriptionEngine.whisper

    func transcribe(
        _ url: URL, locale: Locale, hints: TranscriptionHints?, mayDownload: Bool,
        report: @escaping @Sendable (TranscriptionPhase) -> Void
    ) async throws -> LectureTranscript {
        switch self {
        case .apple:
            do {
                return try await AppleFileTranscriber.transcribe(url, locale: locale, hints: hints, report: report)
            } catch TranscriptionError.localeUnsupported where mayDownload {
                return try await WhisperTranscriber.shared.transcribe(url, hints: hints, report: report)
            }
        case .whisper:
            return try await WhisperTranscriber.shared.transcribe(url, hints: hints, report: report)
        }
    }
}

enum TranscriptionPhase: Equatable, Sendable {
    // Whisper 하나가 메모리를 1GB 차지하므로 모델은 한 번에 하나만 돌린다.
    case waiting
    case downloading(Double)
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

enum AppleFileTranscriber {
    static func transcribe(_ url: URL, locale: Locale, hints: TranscriptionHints?, report: @escaping @Sendable (TranscriptionPhase) -> Void)
        async throws -> LectureTranscript
    {
        guard SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.localeUnsupported
        }
        let transcriber = SpeechTranscriber(
            locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
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

    private static func collect(
        _ transcriber: SpeechTranscriber, duration: TimeInterval,
        report: @Sendable (TranscriptionPhase) -> Void
    ) async throws -> [LectureTranscript.Line] {
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
    // 앱은 locale을 예약해야 언어 모델을 볼 수 있다. 다른 앱이 이미 설치한 모델도 같다. 예약하기 전에는 상태가 미설치로 읽히고 설치를 요청해도 아무것도 돌아오지 않는데, 예전에는 이를 "이 언어는
    // 받아쓸 수 없다"로 읽었다.
    static func request(for transcriber: SpeechTranscriber, locale: Locale) async throws -> AssetInstallationRequest? {
        try await reserve(locale)
        guard await AssetInventory.status(forModules: [transcriber]) != .installed else { return nil }
        return try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
    }

    static func context(_ hints: TranscriptionHints) -> AnalysisContext {
        let context = AnalysisContext()
        context.contextualStrings[.general] = hints.terms
        return context
    }

    private static func reserve(_ locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        if reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) { return }
        if reserved.count >= AssetInventory.maximumReservedLocales, let other = reserved.first {
            _ = await AssetInventory.release(reservedLocale: other)
        }
        _ = try await AssetInventory.reserve(locale: locale)
    }
}
