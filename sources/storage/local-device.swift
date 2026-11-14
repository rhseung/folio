import FolioDomain
import Foundation

public enum LocalDevice {
    static let key = "folio.deviceID"

    public static func id(in defaults: UserDefaults = .standard) -> DeviceID {
        if let stored = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) { return stored }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}
