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
        let k = size / 20
        Group {
            if status == .doing {
                // `circle.lefthalf.filled`는 채움이 고리까지 번져 얼룩처럼 보이므로, 틈을 두어 반쯤 찬 고리로 그린다.
                // 20과 1.7은 20pt SF `circle`을 잰 값이라 다른 상태의 기호와 맞는다.
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

// 사방을 `round`만큼 줄여 그리고, 그 두 배 굵기의 둥근 이음 선으로 원래 크기와 둥근 모서리를 되찾는다. 평평한 쪽만 줄여
// 둥글리면 모양이 오른쪽으로 밀린다.
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
