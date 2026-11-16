import FolioActions
import FolioDomain
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ClassStartOpening: Equatable {
    var link: AppLink
    var placement: LinkPlacement
}
