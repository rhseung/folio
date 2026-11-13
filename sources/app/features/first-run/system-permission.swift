import AVFAudio
import Foundation
import UserNotifications

#if os(iOS)
import UIKit
#endif

// 앱은 아직 캘린더를 읽지 않는다(시험 가져오기는 파일로 한다). 쓰지 않는 권한을 요청하면 심사에서 거절되고 학생도
// 거절하므로, 캘린더는 여기 없다.
enum SystemPermission: CaseIterable, Hashable {
    case notifications, microphone

    enum State: Equatable {
        case unknown
        case allowed
        case denied
    }

    func state() async -> State {
        switch self {
        case .notifications:
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .notDetermined: .unknown
            case .denied: .denied
            default: .allowed
            }
        case .microphone:
            switch AVAudioApplication.shared.recordPermission {
            case .granted: .allowed
            case .denied: .denied
            default: .unknown
            }
        }
    }

    func request() async -> State {
        switch self {
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        case .microphone:
            _ = await AVAudioApplication.requestRecordPermission()
        }
        return await state()
    }

    @MainActor var settingsURL: URL? {
        #if os(macOS)
        switch self {
        case .notifications: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        case .microphone: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        }
        #else
        switch self {
        case .notifications: URL(string: UIApplication.openNotificationSettingsURLString)
        case .microphone: URL(string: UIApplication.openSettingsURLString)
        }
        #endif
    }
}
