import FolioDomain
import SwiftUI

struct Meter: View {
    @Environment(\.accent) private var accent
    let value: Double
    var height: CGFloat = 6

    var body: some View {
        Capsule().fill(accent.tint)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(accent.color).frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: height)
    }
}
