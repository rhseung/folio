import FolioAI
import FolioDomain
import SwiftUI

struct WeightBar: View {
    @Environment(\.accent) private var accent
    let components: [GradeComponent]

    var body: some View {
        let sorted = components.sorted { $0.order < $1.order }
        GeometryReader { proxy in
            let total = max(sorted.map(\.weight).reduce(0, +), 1)
            HStack(spacing: Theme.Space.xxs) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { i, c in
                    accent.color.opacity(max(0.15, 1 - Double(i) * 0.2))
                        .frame(width: max(0, proxy.size.width * c.weight / total - 2))
                        .help("\(c.name) \(c.weight.formatted())%")
                }
            }
        }
        .frame(height: 10)
        .clipShape(.capsule)
    }
}
