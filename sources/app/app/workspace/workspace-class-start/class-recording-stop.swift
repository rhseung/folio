import FolioActions
import FolioDomain
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ClassRecordingStop: Equatable {
    var recording: UUID
    var at: Date
}
