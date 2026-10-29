import SwiftUI

/// A number changed by dragging sideways across it, one step every few points with a tick under the finger.
/// A click turns it into a text field for typing an exact value.
struct ScrubField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var fractionLength = 0
    var width: CGFloat = 80
    @State private var start: Double?
    @State private var typing = false
    @FocusState private var focused: Bool

    static let pointsPerStep: CGFloat = 6

    var text: String { value.formatted(.number.grouping(.never).precision(.fractionLength(fractionLength))) }

    var body: some View {
        Group {
            if typing {
                TextField("", value: $value, format: .number.grouping(.never))
                    .focused($focused)
                    .onSubmit { typing = false }
                    .onChange(of: focused) { _, now in if !now { typing = false } }
                    .onAppear { focused = true }
            } else {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "chevron.left").opacity(value > range.lowerBound ? 0.5 : 0.15)
                    Text(text).rolling(text).frame(maxWidth: .infinity, alignment: .trailing)
                    Image(systemName: "chevron.right").opacity(value < range.upperBound ? 0.5 : 0.15)
                }
                .imageScale(.small)
                .contentShape(.capsule)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { g in
                            let base = start ?? value
                            start = base
                            let steps = (g.translation.width / Self.pointsPerStep).rounded()
                            let next = min(max(base + steps * step, range.lowerBound), range.upperBound)
                            // Snapped to the step so float drift never shows as 4.299999.
                            value = (next / step).rounded() * step
                        }
                        .onEnded { _ in start = nil }
                )
                .onTapGesture { typing = true }
                #if os(macOS)
                .pointerStyle(.columnResize)
                #endif
                .help(Text(.designDragOrTypeHelp))
            }
        }
        .pill(width: width)
        .sensoryFeedback(.levelChange, trigger: value)
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step) { Text(.designValue) }
        }
    }
}
