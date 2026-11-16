import AVFoundation
import FolioDomain
import Foundation
import Observation
@preconcurrency import WhisperKit

// 찾아보지 않고 기억해 둔다. 중간에 끊긴 다운로드도 같은 모양의 폴더를 남기기 때문이다.
@MainActor @Observable
final class WhisperModel {
    static let shared = WhisperModel()
    private static let readyKey = "folio.whisperModelReady"

    private(set) var ready = UserDefaults.standard.bool(forKey: readyKey)
    var downloading: Double?
    var busy = false
    private(set) var failure: String?

    func finishDownload(ready: Bool) {
        self.ready = ready
        downloading = nil
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
