import AVFoundation
import FolioDomain
import Speech

enum TranscriptionPhase: Equatable, Sendable {
    // Whisper 하나가 메모리를 1GB 차지하므로 모델은 한 번에 하나만 돌린다.
    case waiting
    case downloading(Double)
    case preparing
    case transcribing(Double)
}
