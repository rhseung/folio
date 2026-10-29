import SwiftUI

/// A grade picked on a track of stops, lowest on the left. The fill turns from red through amber to green as it rises,
/// each stop clicks under the finger, and pressing the picked stop again clears it back to 미정.
struct GradeSteps: View {
    struct Stop: Identifiable {
        let id: UUID
        let symbol: String
    }

    @Binding var selection: UUID?
    /// Lowest first.
    let stops: [Stop]
    /// Off the scale (W in a letter-graded course): small buttons before the track.
    var extras: [Stop] = []
    @State private var before: UUID??

    static let spacing: CGFloat = 22
    static let thumb: CGFloat = 14

    var index: Int? { stops.firstIndex { $0.id == selection } }

    var extra: Stop? { extras.first { $0.id == selection } }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach(extras) { e in
                Button(e.symbol) { selection = selection == e.id ? nil : e.id }
                    .buttonStyle(.pointing(.plain))
                    .font(Theme.Typeface.caption.weight(.semibold))
                    .foregroundStyle(selection == e.id ? Theme.Palette.text : Theme.Palette.textTertiary)
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xxs)
                    .background(selection == e.id ? Theme.Palette.fill : .clear, in: .capsule)
            }
            track
            Text(index.map { stops[$0].symbol } ?? extra?.symbol ?? "미정")
                .font(Theme.Typeface.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(index.map(color) ?? (extra == nil ? Theme.Palette.textTertiary : Theme.Palette.text))
                .frame(width: 30, alignment: .leading)
                .contentTransition(.numericText())
        }
        // Its own size: in a narrow row the off-scale buttons were squeezed before the row's label gave way.
        .fixedSize()
        .animation(.snappy(duration: 0.22), value: selection)
        .sensoryFeedback(.levelChange, trigger: selection)
        .accessibilityElement()
        .accessibilityLabel("성적")
        .accessibilityValue(index.map { stops[$0].symbol } ?? extra?.symbol ?? "미정")
        .accessibilityAdjustableAction { direction in
            let i = index ?? -1
            let next = direction == .increment ? min(i + 1, stops.count - 1) : max(i - 1, 0)
            selection = stops[next].id
        }
    }

    var track: some View {
        let width = Self.spacing * CGFloat(max(stops.count - 1, 0))
        return ZStack(alignment: .leading) {
            Capsule().fill(Theme.Palette.line).frame(width: width + Self.thumb, height: 6)
            if let i = index {
                Capsule().fill(color(i).gradient).frame(width: Self.spacing * CGFloat(i) + Self.thumb, height: 6)
            }
            ForEach(stops.indices, id: \.self) { i in
                Circle()
                    .fill(index.map { i <= $0 } == true ? Theme.Palette.onFill.opacity(0.7) : Theme.Palette.textTertiary.opacity(0.6))
                    .frame(width: 4, height: 4)
                    .offset(x: Self.spacing * CGFloat(i) + Self.thumb / 2 - 2)
            }
            if let i = index {
                Circle()
                    .fill(color(i))
                    .overlay(Circle().stroke(Theme.Palette.card, lineWidth: 2.5))
                    .shadow(color: color(i).opacity(0.5), radius: 4)
                    .frame(width: Self.thumb, height: Self.thumb)
                    .offset(x: Self.spacing * CGFloat(i))
            }
        }
        .frame(width: width + Self.thumb, height: 22)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if before == nil { before = .some(selection) }
                    selection = stops[stop(at: g.location.x)].id
                }
                .onEnded { g in
                    // A press on the stop already picked, without dragging, clears the grade.
                    if abs(g.translation.width) < 4, before == .some(stops[stop(at: g.location.x)].id) { selection = nil }
                    before = nil
                }
        )
        .pointingHand()
        .help("눌러서 고르고, 고른 칸을 다시 누르면 미정")
    }

    func stop(at x: CGFloat) -> Int {
        min(max(Int(((x - Self.thumb / 2) / Self.spacing).rounded()), 0), stops.count - 1)
    }

    func color(_ i: Int) -> Color {
        let t = stops.count > 1 ? Double(i) / Double(stops.count - 1) : 1
        return t < 0.5 ? Theme.Palette.danger.mix(with: Theme.Palette.warning, by: t * 2)
                       : Theme.Palette.warning.mix(with: Theme.Palette.success, by: (t - 0.5) * 2)
    }
}

extension GradeSteps {
    /// Grades best first, as the catalog lists them: those with points make the track, the rest stand apart unless
    /// nothing has points (S/U), where all of them do.
    init(selection: Binding<UUID?>, grades: [(id: UUID, symbol: String, scored: Bool)]) {
        let scored = grades.filter(\.scored)
        let track = scored.isEmpty ? grades : scored
        self.init(selection: selection, stops: track.reversed().map { Stop(id: $0.id, symbol: $0.symbol) },
                  extras: scored.isEmpty ? [] : grades.filter { !$0.scored }.map { Stop(id: $0.id, symbol: $0.symbol) })
    }
}
