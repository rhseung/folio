import FolioDomain
import SwiftUI

enum RecordingTime {
    static func label(_ seconds: TimeInterval) -> String {
        ClockText.duration(Int(max(seconds, 0)))
    }
}
