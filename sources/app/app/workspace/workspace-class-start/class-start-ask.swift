import FolioActions
import FolioDomain
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ClassStartAsk: Identifiable, Equatable {
    let id = UUID()
    let course: UUID
    let session: UUID
    var opens: [ClassStartOpening] = []
    var split: PaneLayout?
    var front = false
    var asksRecording = false
    var stopAt: Date?
    var title = ""

    var opensPages: Bool { !opens.isEmpty || split != nil }
}
