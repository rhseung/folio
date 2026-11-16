import FolioDomain
import FolioMarkdown
import SwiftUI

extension MathCategory {
    var label: String {
        switch self {
        case .snippets: String(localized: .notesMathCategorySnippets)
        case .greek: String(localized: .notesMathCategoryGreek)
        case .relations: String(localized: .notesMathCategoryRelations)
        case .operators: String(localized: .notesMathCategoryOperators)
        case .arrows: String(localized: .notesMathCategoryArrows)
        case .functions: String(localized: .notesMathCategoryFunctions)
        case .fonts: String(localized: .notesMathCategoryFonts)
        case .symbols: String(localized: .notesMathCategorySymbols)
        }
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
