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
