import AVFoundation
import FolioDomain
import Speech

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
