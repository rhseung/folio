import SwiftUI

struct NumberField: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double
    var fractionLength = 0
    var width: CGFloat = 80
    var magnitude = false
    @State private var start: Double?
    @State private var typing = false
    @FocusState private var focused: Bool

    static let pointsPerStep: CGFloat = 6

    var text: String { shown.formatted(.number.grouping(.never).precision(.fractionLength(fractionLength))) }

    var shown: Double { magnitude ? abs(value) : value }

    var typed: Binding<Double> {
        guard magnitude else { return $value }
        return Binding(
            get: { abs(value) },
            set: { n in
                value = min(max((value < 0 ? -1 : 1) * abs(n), bounds.lowerBound), bounds.upperBound)
            })
    }

    var body: some View {
        Group {
            if typing {
                TextField("", value: typed, format: .number.grouping(.never))
                    .focused($focused)
                    .onSubmit { typing = false }
                    .onChange(of: focused) { _, now in if !now { typing = false } }
                    .onAppear { focused = true }
            } else {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "chevron.left").opacity(value > bounds.lowerBound ? 0.5 : 0.15)
                    Text(text).rolling(text).frame(maxWidth: .infinity, alignment: .trailing)
                    Image(systemName: "chevron.right").opacity(value < bounds.upperBound ? 0.5 : 0.15)
                }
                .imageScale(.small)
                .contentShape(.capsule)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { g in
                            let base = start ?? value
                            start = base
                            let steps = (g.translation.width / Self.pointsPerStep).rounded()
                            let next = min(max(base + steps * step, bounds.lowerBound), bounds.upperBound)
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
            Slider(value: $value, in: bounds, step: step) { Text(.designValue) }
        }
    }
}

extension NumberField {
    init(
        value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double, fractionLength: Int = 0, width: CGFloat = 80,
        magnitude: Bool = false
    ) {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.fractionLength = fractionLength
        self.width = width
        self.magnitude = magnitude
    }

    init(value: Binding<Int>, in bounds: ClosedRange<Int>, step: Int = 1, width: CGFloat = 64, magnitude: Bool = false) {
        self.init(
            value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = min(max(Int($0.rounded()), bounds.lowerBound), bounds.upperBound) }),
            in: Double(bounds.lowerBound)...Double(bounds.upperBound), step: Double(step), width: width, magnitude: magnitude)
    }
}
