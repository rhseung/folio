#if DEBUG
import FolioDomain
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor @Observable final class PaneBundleHook {
    static let shared = PaneBundleHook()
    var listing = false
}
#endif
