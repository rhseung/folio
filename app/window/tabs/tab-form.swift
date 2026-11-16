import FolioDomain
import SwiftUI

enum TabForm: CaseIterable {
    case full, icons, stacked

    init(_ fit: TabFit.Layout) {
        self = !fit.iconsOnly ? .full : fit.stacked ? .stacked : .icons
    }
}
