import FolioDomain
import SwiftUI

extension AssignmentStatus {
    @MainActor static let steps: [StepToggle<AssignmentStatus>.Option] = [
        .init(value: .todo, label: String(localized: .assignmentStatusTodo), tint: Theme.Palette.textSecondary),
        .init(value: .doing, label: String(localized: .assignmentStatusDoing), tint: Theme.Palette.warning),
        .init(value: .submitted, label: String(localized: .assignmentStatusSubmitted), tint: Theme.Palette.success),
        .init(value: .graded, label: String(localized: .assignmentStatusGraded), tint: Theme.Series.one),
    ]

    var label: String {
        switch self {
        case .todo: String(localized: .assignmentStatusTodo)
        case .doing: String(localized: .assignmentStatusDoing)
        case .submitted: String(localized: .assignmentStatusSubmitted)
        case .graded: String(localized: .assignmentStatusGraded)
        }
    }

    /// The circle a todo app draws: empty, half full, checked, then the seal once a score is back.
    /// `AssignmentStatusIcon` draws doing itself; this symbol is for menus.
    var symbol: String {
        switch self {
        case .todo: "circle"
        case .doing: "circle.lefthalf.filled"
        case .submitted: "checkmark.circle.fill"
        case .graded: "checkmark.seal.fill"
        }
    }

    @MainActor var tint: Color { Self.steps.first { $0.value == self }?.tint ?? Theme.Palette.textTertiary }
}

struct AssignmentStatusIcon: View {
    let status: AssignmentStatus
    var tint: Color?
    var size: CGFloat = 20

    var body: some View {
        // The half-done ring's measurements are for 20pt; they scale with the symbol.
        let k = size / 20
        Group {
            if status == .doing {
                // circle.lefthalf.filled runs the fill into the ring and reads as a blot; a gap keeps it a ring that is half done.
                // 20 and 1.7 are SF `circle` at 20pt, measured, so it lines up with the other states' symbols.
                ZStack {
                    Circle().strokeBorder(lineWidth: 1.7 * k)
                    HalfDisc(round: k).fill()
                        .overlay { HalfDisc(round: k).stroke(style: StrokeStyle(lineWidth: 2 * k, lineJoin: .round)) }
                        .padding(2.9 * k)
                }
                .frame(width: size, height: size)
            } else {
                Image(systemName: status.symbol)
                    .font(.system(size: size))  // design: one-off, the status symbol is the row's button
            }
        }
        .foregroundStyle(tint ?? (status == .todo ? Theme.Palette.textTertiary : status.tint))
        .frame(width: size + 4, height: size + 4)
    }
}

/// The right half of the rect's circle, drawn `round` short on every side so a round-joined stroke of twice that
/// brings it back to full size with soft corners. Rounding by shrinking only the flat side would push the shape right.
private struct HalfDisc: Shape {
    let round: CGFloat

    func path(in rect: CGRect) -> Path {
        let rho = rect.width / 2 - round, theta = acos(round / rho)
        var p = Path()
        p.addRelativeArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rho, startAngle: .radians(-theta), delta: .radians(2 * theta))
        p.closeSubpath()
        return p
    }
}
