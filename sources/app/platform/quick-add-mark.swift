#if os(macOS)
import AppKit
import SwiftUI

struct QuickAddMark: Equatable {
    var range: NSRange
    var fill: Color
}
#endif
