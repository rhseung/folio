import AVFoundation
import FolioDomain
import Speech

enum TranscriptionError: LocalizedError {
    case localeUnsupported, unreadableAudio

    var errorDescription: String? {
        switch self {
        case .localeUnsupported: String(localized: .recordingErrorLocaleUnsupported)
        case .unreadableAudio: String(localized: .recordingErrorUnreadableAudio)
        }
    }
}
