import FolioAI
import FolioDomain
import SwiftUI

struct PlaceIcon: View {
    let place: Crumb
    var tint: Color?

    var body: some View {
        if let dot = place.dot {
            CourseMark(icon: place.symbol, color: tint ?? dot)
        } else {
            LineIcon(symbol: place.symbol ?? "questionmark.folder").foregroundStyle(tint ?? Theme.Palette.chromeIcon)
        }
    }
}
