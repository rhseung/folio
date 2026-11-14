import FolioDomain
import SwiftUI

enum MemoryPressure {
    #if os(macOS)
    static let warning = Notification.Name("FolioMemoryPressure")
    @MainActor private static var source: DispatchSourceMemoryPressure?

    // Mac에는 따로 들을 memory warning이 없다.
    @MainActor static func start() {
        guard source == nil else { return }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { NotificationCenter.default.post(name: warning, object: nil) }
        pressure.resume()
        source = pressure
    }

    static var publisher: NotificationCenter.Publisher { NotificationCenter.default.publisher(for: warning) }
    #else
    static func start() {}
    static var publisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
    }
    #endif
}
