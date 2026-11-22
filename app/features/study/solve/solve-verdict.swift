import FolioDomain
import SwiftUI

struct SolveVerdict: View {
    @Bindable var model: SolveModel
    let graded: SolveModel.Graded

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                Badge(graded.verdict.label, tone: graded.verdict.tone, solid: true)
                Text(.solveBasis(graded.basis.label)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                Spacer(minLength: Theme.Space.m)
                // 채점이 틀렸으면 고친다. 고친 판정은 직접 채점으로 남는다.
                SegmentedControl(
                    selection: Binding(get: { graded.verdict }, set: { model.override($0) }),
                    options: Verdict.allCases.map { ($0, $0.label) }, size: .small)
            }
            if model.staysRecheck {
                Label(String(localized: .solveRecheckNotice), systemImage: "arrow.clockwise")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.warning)
            }
            if !graded.feedback.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(Array(graded.feedback.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            Text(verbatim: "•").foregroundStyle(Theme.Palette.textTertiary)
                            StudyText(text: line, look: .prose)
                        }
                    }
                }
            }
            if graded.verdict.isMistake {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Caption(String(localized: .solveReason))
                    SegmentedControl(
                        selection: Binding(get: { graded.reason }, set: { if let r = $0 { model.setReason(r) } }),
                        options: model.reasons.map { (Optional($0), $0.label) }, layout: .flow)
                }
            }
            if let text = model.solutionText {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Caption(String(localized: .solveSolution))
                    StudyText(text: text).textSelection(.enabled)
                }
            }
            HStack(spacing: Theme.Space.s) {
                if let page = model.solutionPage {
                    Button(.solveShowSolution, systemImage: "text.book.closed") { model.show(page) }.buttonStyle(.secondary)
                }
                ForEach(model.lecturePages, id: \.self) { page in
                    Button(String(localized: .solveLecturePage(page.page)), systemImage: "book") { model.show(page) }.buttonStyle(
                        .secondary)
                }
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.Palette.page, in: .rect(cornerRadius: Theme.Radius.card))
    }
}
