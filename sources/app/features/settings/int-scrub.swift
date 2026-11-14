import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

struct IntScrub: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 64

    var body: some View {
        ScrubField(
            value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
            range: Double(range.lowerBound)...Double(range.upperBound), step: 1, width: width)
    }
}
