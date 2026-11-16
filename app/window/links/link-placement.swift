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
    case tabBehind
    case window

    // 메뉴가 보이는 여는 자리다. 뒤에서 여는 새 탭은 ⌘-클릭으로만 연다.
    static let menu: [LinkPlacement] = [.here, .beside, .tab, .window]

    init(_ click: LinkClick) {
        self =
            switch click {
            case .here: .here
            case .tabBehind: .tabBehind
            case .tab: .tab
            case .beside: .beside
            }
    }

    var title: String {
        switch self {
        case .here: String(localized: .linkOpenHere)
        case .beside: String(localized: .linkOpenBeside)
        case .tab, .tabBehind: String(localized: .linkOpenTab)
        case .window: String(localized: .linkOpenWindow)
        }
    }

    var symbol: String {
        switch self {
        case .here: "arrow.right.circle"
        case .beside: "rectangle.split.2x1"
        case .tab, .tabBehind: "plus.rectangle.on.rectangle"
        case .window: "macwindow.badge.plus"
        }
    }
}
