import AVFAudio
import Foundation
import UserNotifications

#if os(iOS)
import UIKit
#endif

/// What the app asks the system for. Calendar isn't here: the app reads no calendar yet (the exam import goes through a
/// file), and asking for access it never uses would be refused by review and by the student.
enum SystemPermission: CaseIterable, Hashable {
    case notifications, microphone

    enum State: Equatable {
        /// Not asked yet: 허용 asks.
        case unknown
        case allowed
        /// Turned down: only the system's settings can turn it on now.
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

    /// The system settings page that turns it back on.
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
