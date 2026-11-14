import FolioDomain
import SwiftUI

#if os(macOS)
import AppKit
import WebKit

@MainActor final class WindowHost {
    weak var window: NSWindow?
}
#endif
