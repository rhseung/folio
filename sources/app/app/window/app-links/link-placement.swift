import FolioDomain
import FolioMarkdown
import FolioStorage
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum LinkPlacement: CaseIterable {
    case here
    case beside
    case tab
    case window

    var title: String {
        switch self {
        case .here: String(localized: .linkOpenHere)
        case .beside: String(localized: .linkOpenBeside)
        case .tab: String(localized: .linkOpenTab)
        case .window: String(localized: .linkOpenWindow)
        }
    }

    var symbol: String {
        switch self {
        case .here: "arrow.right.circle"
        case .beside: "rectangle.split.2x1"
        case .tab: "plus.rectangle.on.rectangle"
        case .window: "macwindow.badge.plus"
        }
    }
}
