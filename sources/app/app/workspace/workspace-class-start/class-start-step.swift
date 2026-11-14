import FolioActions
import FolioDomain
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ClassStartStep: Equatable {
    var ask: ClassStartAsk
    var records = false
}
