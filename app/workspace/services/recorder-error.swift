import AVFoundation
import FolioDomain
import Speech

#if os(iOS)
import UIKit
#endif

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
