import FolioDomain
import SwiftUI

// 계획 항목에서 바로 푸는 단추다. 단원 페이지의 계획 블록과 오늘 화면이 함께 쓴다.
struct PlanSolveButton: View {
    let course: UUID
    let item: UUID
    let solve: PlanSolve
    @Environment(\.itemSheets) private var sheets

    var body: some View {
        Button(title, systemImage: symbol) {
            if solve.cards {
                sheets.present(.flipCards(course: course, unit: nil))
            } else {
                sheets.present(.solve(SolveRequest(plan: solve, course: course, item: item)))
            }
        }
        .buttonStyle(.secondary)
    }

    var title: String {
        if solve.cards { return String(localized: .planSolveCards) }
        return String(localized: solve.mode == .mock ? .planSolveMock : .planSolveProblems)
    }

    var symbol: String { solve.cards ? "rectangle.on.rectangle.angled" : solve.mode == .mock ? "timer" : "pencil.and.list.clipboard" }
}
